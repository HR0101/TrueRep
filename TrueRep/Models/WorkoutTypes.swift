//
//  WorkoutTypes.swift
//  TrueRep
//
//  トレーニング解析の結果・状態を表す型定義
//

import Foundation

/// 身体の向き（カメラに対する撮影アングル）
nonisolated enum BodyOrientation: String, Sendable {
  /// 正面（カメラに向かって立っている）
  case front
  /// 側面（横向き）
  case side
  /// 斜め（中間的な向き）
  case oblique
  /// 判定不能（関節が検出できない）
  case unknown

  /// 画面表示用のラベル
  var label: String {
    switch self {
    case .front: return "正面"
    case .side: return "側面"
    case .oblique: return "斜め"
    case .unknown: return "—"
    }
  }
}

/// フォームの問題の種類
nonisolated enum FormFault: String, CaseIterable, Sendable, Hashable {
  /// 膝が内側に入っている（ニーイン）
  case kneeValgus
  /// 左右のバランスが崩れている
  case lateralImbalance
  /// 体幹が前傾しすぎている（背中の丸まりの兆候）
  case excessiveLean
  /// しゃがみが浅い（可動域不足）
  case shallowDepth

  /// 画面表示用の短い警告文（トレーニング中でも一瞬で読めるよう最小限にする）
  var message: String {
    switch self {
    case .kneeValgus: return "膝が内側"
    case .lateralImbalance: return "左右バランス"
    case .excessiveLean: return "前傾しすぎ"
    case .shallowDepth: return "もっと深く"
    }
  }
}

/// レップ動作の状態（スクワットの状態機械）
nonisolated enum RepPhase: String, Sendable {
  /// 立位（開始位置）
  case standing
  /// 下降中
  case descending
  /// ボトム位置
  case bottom
  /// 上昇中
  case ascending
}

/// 1レップの記録
nonisolated struct RepRecord: Sendable {
  /// 何レップ目か（1始まり）
  let index: Int
  /// レップにかかった時間（秒）
  let duration: TimeInterval
  /// 最深部の膝角度（度）
  let bottomKneeAngle: Double
  /// 可動域（ROM）を満たしたか
  let metDepth: Bool
}

/// 解析エンジンからUIへ流すフレームごとの更新情報
nonisolated struct WorkoutUpdate: Sendable {
  /// 姿勢検出結果（骨格描画用）
  let pose: BodyPose?
  /// 現在の身体の向き
  let orientation: BodyOrientation
  /// 現在のレップ動作の状態
  let phase: RepPhase
  /// 有効レップ数（ROMを満たしたもののみ）
  let repCount: Int
  /// 現在のテンポ（BPM，算出不能時はnil）
  let bpm: Double?
  /// 現在検知されているフォームの問題（空なら良好）
  let activeFaults: Set<FormFault>
  /// 現在の膝角度（度，検出不能時はnil）
  let kneeAngle: Double?
}

/// セッション終了時のサマリー
nonisolated struct WorkoutSummary: Sendable {
  /// 総レップ数（有効レップのみ）
  let totalReps: Int
  /// 平均BPM（算出不能時はnil）
  let averageBPM: Double?
  /// フォーム警告の発生回数（種類別）
  let faultCounts: [FormFault: Int]
  /// セッションの総時間（秒）
  let duration: TimeInterval
  /// 全レップの記録
  let reps: [RepRecord]
}
