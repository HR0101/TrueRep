//
//  OrientationDetector.swift
//  TrueRep
//
//  カメラに対する身体の向き（正面／側面／斜め）の自動判定
//

import Foundation

/// 身体の向きを姿勢データから推定する
nonisolated enum OrientationDetector {

  /// 肩幅÷体幹長の比率がこの値以上なら正面とみなす
  static let frontThreshold: Double = 0.45
  /// 肩幅÷体幹長の比率がこの値以下なら側面とみなす
  static let sideThreshold: Double = 0.22

  /// 姿勢データから身体の向きを推定する
  ///
  /// 正面を向いているほど画面上の肩幅は広く写り，横を向くほど狭く写る．
  /// 距離に依存しないよう，肩幅を体幹長（肩中点〜腰中点）で正規化して判定する．
  static func detect(from pose: BodyPose) -> BodyOrientation {
    guard
      let leftShoulder = pose[.leftShoulder],
      let rightShoulder = pose[.rightShoulder],
      let shoulderCenter = pose.shoulderCenter,
      let hipCenter = pose.hipCenter
    else {
      return .unknown
    }

    // 肩幅（画面上の水平距離ではなく2点間距離を使い，傾きの影響を抑える）
    let shoulderDx = leftShoulder.position.x - rightShoulder.position.x
    let shoulderDy = leftShoulder.position.y - rightShoulder.position.y
    let shoulderWidth = sqrt(shoulderDx * shoulderDx + shoulderDy * shoulderDy)

    // 体幹長（肩中点〜腰中点）
    let torsoDx = shoulderCenter.x - hipCenter.x
    let torsoDy = shoulderCenter.y - hipCenter.y
    let torsoLength = sqrt(torsoDx * torsoDx + torsoDy * torsoDy)
    guard torsoLength > 0.02 else { return .unknown }

    let ratio = shoulderWidth / torsoLength
    if ratio >= frontThreshold {
      return .front
    } else if ratio <= sideThreshold {
      return .side
    } else {
      return .oblique
    }
  }
}

/// 向き判定のチラつきを抑えるスムーザー（多数決方式）
nonisolated struct OrientationSmoother: Sendable {
  /// 直近の判定結果を保持する個数
  private static let windowSize = 15
  /// 直近の判定履歴
  private var history: [BodyOrientation] = []
  /// 現在の確定値
  private(set) var current: BodyOrientation = .unknown

  /// 新しい判定結果を追加し，多数決で確定値を更新する
  mutating func add(_ orientation: BodyOrientation) -> BodyOrientation {
    history.append(orientation)
    if history.count > Self.windowSize {
      history.removeFirst(history.count - Self.windowSize)
    }

    // unknown以外で最頻の向きを採用する
    var counts: [BodyOrientation: Int] = [:]
    for item in history where item != .unknown {
      counts[item, default: 0] += 1
    }
    if let best = counts.max(by: { $0.value < $1.value }), best.value >= history.count / 3 {
      current = best.key
    } else {
      current = .unknown
    }
    return current
  }

  /// 履歴をリセットする
  mutating func reset() {
    history.removeAll()
    current = .unknown
  }
}
