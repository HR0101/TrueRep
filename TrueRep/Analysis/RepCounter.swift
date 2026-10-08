//
//  RepCounter.swift
//  TrueRep
//
//  腰のY座標の時系列からレップ（反復回数）を検出する状態機械
//

import Foundation

/// レップカウントの状態機械
///
/// 腰のY座標（正規化座標，上が1）の上下動を追跡し，
/// 「立位→下降→ボトム→上昇→立位」の1サイクルを1レップとして数える．
/// 設定した可動域（ROM）を満たした場合のみ有効レップとしてカウントする．
nonisolated struct RepCounter: Sendable {

  /// 判定パラメーター
  nonisolated struct Configuration: Sendable {
    /// 下降開始とみなす立位からの下げ幅（体幹長に対する比率）
    var descentTriggerRatio: Double = 0.15
    /// 立位復帰とみなすボトムからの戻り率（0〜1）
    var ascentCompleteRatio: Double = 0.85
    /// 有効レップとみなす最深部の膝角度の上限（度）．これより深く曲げる必要がある
    var maxKneeAngleForValidRep: Double = 110
    /// ノイズ除去用の指数移動平均の係数（0〜1，大きいほど追従が速い）
    var smoothingFactor: Double = 0.4
    /// 1レップの最短時間（秒）．これ未満の動きはノイズとして無視する
    var minimumRepDuration: TimeInterval = 0.6

    init() {}
  }

  private let config: Configuration

  /// 現在の状態
  private(set) var phase: RepPhase = .standing
  /// 有効レップの記録
  private(set) var reps: [RepRecord] = []
  /// 有効レップ数
  var repCount: Int { reps.count }

  /// 平滑化済みの腰Y座標
  private var smoothedY: Double?
  /// 立位時の基準Y座標（動的に更新）
  private var standingY: Double?
  /// 現在のレップの開始時刻
  private var repStartTime: TimeInterval?
  /// 現在のレップ中の最小Y（最深部）
  private var lowestY: Double?
  /// 現在のレップ中の最小膝角度（最深部）
  private var minKneeAngle: Double = 180
  /// 体幹長（しきい値の正規化に使用）
  private var torsoLength: Double = 0.25

  init(configuration: Configuration = Configuration()) {
    self.config = configuration
  }

  /// 新しいフレームの計測値を取り込み，状態を更新する
  /// - Parameters:
  ///   - hipY: 腰中点のY座標（正規化，上が大きい）
  ///   - kneeAngle: 膝角度（度，検出不能時はnil）
  ///   - torso: 体幹長（正規化，検出不能時はnil）
  ///   - timestamp: フレームのタイムスタンプ（秒）
  /// - Returns: このフレームで新しい有効レップが完了した場合はその記録
  mutating func process(
    hipY: Double,
    kneeAngle: Double?,
    torso: Double?,
    timestamp: TimeInterval
  ) -> RepRecord? {
    // 体幹長を更新（立位時のみ．しゃがむと見かけの体幹長が変わるため）
    if phase == .standing, let torso, torso > 0.05 {
      torsoLength = torso
    }

    // 指数移動平均でノイズを除去する
    let y: Double
    if let previous = smoothedY {
      y = previous + config.smoothingFactor * (hipY - previous)
    } else {
      y = hipY
    }
    smoothedY = y

    // 膝角度の最深値を追跡する
    if let kneeAngle, phase == .descending || phase == .bottom {
      minKneeAngle = min(minKneeAngle, kneeAngle)
    }

    switch phase {
    case .standing:
      // 立位基準を緩やかに追従させる（立ち位置の微調整に対応）
      if let standing = standingY {
        standingY = standing + 0.05 * (y - standing)
      } else {
        standingY = y
      }
      // 基準から一定以上下がったら下降開始
      if let standing = standingY, standing - y > config.descentTriggerRatio * torsoLength {
        phase = .descending
        repStartTime = timestamp
        lowestY = y
        minKneeAngle = kneeAngle ?? 180
      }

    case .descending:
      if let lowest = lowestY {
        if y < lowest {
          // まだ下降中
          lowestY = y
        } else if lowest < y, yIsRising(current: y, lowest: lowest) {
          // 反転を検知したらボトムへ
          phase = .bottom
        }
      }

    case .bottom:
      if let lowest = lowestY, y < lowest {
        // さらに下がった場合は下降に戻す
        lowestY = y
        phase = .descending
      } else {
        phase = .ascending
      }

    case .ascending:
      guard let standing = standingY, let lowest = lowestY else {
        // 基準値が失われた場合は立位に戻して仕切り直す
        resetCurrentRep()
        phase = .standing
        return nil
      }
      // ボトムから立位基準までの戻り率を計算する
      let totalDrop = standing - lowest
      guard totalDrop > 0 else {
        resetCurrentRep()
        phase = .standing
        return nil
      }
      let recovery = (y - lowest) / totalDrop
      if recovery >= config.ascentCompleteRatio {
        // 1レップ完了
        let record = completeRep(at: timestamp)
        phase = .standing
        return record
      }
      // 立位に戻る前に再度下がり始めた場合（途中で切り返した場合）は下降扱いに戻す
      if y < lowest {
        lowestY = y
        phase = .descending
      }
    }

    return nil
  }

  /// 状態をすべてリセットする
  mutating func reset() {
    phase = .standing
    reps = []
    smoothedY = nil
    standingY = nil
    resetCurrentRep()
  }

  /// 上昇への反転を判定する（最深部からわずかに戻ったかどうか）
  private func yIsRising(current: Double, lowest: Double) -> Bool {
    current - lowest > 0.02 * torsoLength
  }

  /// 現在のレップの一時状態をクリアする
  private mutating func resetCurrentRep() {
    repStartTime = nil
    lowestY = nil
    minKneeAngle = 180
  }

  /// レップ完了処理．ROMと最短時間を満たす場合のみ記録に追加する
  private mutating func completeRep(at timestamp: TimeInterval) -> RepRecord? {
    defer { resetCurrentRep() }
    guard let start = repStartTime else { return nil }

    let duration = timestamp - start
    let metDepth = minKneeAngle <= config.maxKneeAngleForValidRep
    guard duration >= config.minimumRepDuration else { return nil }

    let record = RepRecord(
      index: reps.count + 1,
      duration: duration,
      bottomKneeAngle: minKneeAngle,
      metDepth: metDepth
    )
    // ROMを満たした場合のみ有効レップとして数える
    if metDepth {
      reps.append(record)
      return record
    }
    return RepRecord(index: 0, duration: duration, bottomKneeAngle: minKneeAngle, metDepth: false)
  }
}
