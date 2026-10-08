//
//  AnalysisEngine.swift
//  TrueRep
//
//  姿勢データからレップ・BPM・フォームを統合的に解析するエンジン
//

import Foundation

/// 解析エンジン
///
/// 姿勢推定結果（BodyPose）を受け取り，向き判定・レップカウント・
/// テンポ算出・フォーム判定を統合して1つの更新情報（WorkoutUpdate）にまとめる．
/// バックグラウンドの推論パイプラインから呼ばれるためactorとして実装し，
/// 内部状態へのデータ競合を防ぐ．
actor AnalysisEngine {

  /// レップカウントの状態機械
  private var repCounter = RepCounter()
  /// テンポ（BPM）の算出
  private var tempoAnalyzer = TempoAnalyzer()
  /// 向き判定のスムーザー
  private var orientationSmoother = OrientationSmoother()
  /// フォーム警告のチラつき防止
  private var faultDebouncer = FaultDebouncer()
  /// セッション開始時刻
  private var sessionStart: TimeInterval?
  /// 浅すぎたレップの回数（サマリー用）
  private var shallowRepCount = 0

  /// 1フレーム分の姿勢データを解析し，UI向けの更新情報を返す
  func process(pose: BodyPose) -> WorkoutUpdate {
    if sessionStart == nil {
      sessionStart = pose.timestamp
    }

    // 向きの判定（チラつき防止のため多数決で平滑化する）
    let rawOrientation = OrientationDetector.detect(from: pose)
    let orientation = orientationSmoother.add(rawOrientation)

    // 主要関節が見えない場合は解析をスキップして現状を返す
    guard let hipCenter = pose.hipCenter, pose.hasLowerBody else {
      return makeUpdate(pose: pose, orientation: orientation, kneeAngle: nil)
    }

    // 角度・体幹長の計算
    let kneeAngle = AngleCalculator.kneeAngle(of: pose)
    var torsoLength: Double?
    if let shoulder = pose.shoulderCenter {
      let dx = shoulder.x - hipCenter.x
      let dy = shoulder.y - hipCenter.y
      torsoLength = sqrt(dx * dx + dy * dy)
    }

    // レップカウントの状態機械を進める
    let completedRep = repCounter.process(
      hipY: hipCenter.y,
      kneeAngle: kneeAngle,
      torso: torsoLength,
      timestamp: pose.timestamp
    )

    // レップ完了時の処理
    if let rep = completedRep {
      if rep.metDepth {
        // 有効レップ: テンポ履歴に追加する
        tempoAnalyzer.add(duration: rep.duration)
      } else {
        // 浅すぎたレップ: フォーム警告として記録する
        shallowRepCount += 1
      }
    }

    // フォーム判定（向きに応じてルールを自動切替する）
    var detected = FormAnalyzer.analyze(pose: pose, orientation: orientation, phase: repCounter.phase)
    if let rep = completedRep, !rep.metDepth {
      // 浅いレップの完了直後は深さ警告を出す
      detected.insert(.shallowDepth)
    }
    _ = faultDebouncer.update(with: detected)

    return makeUpdate(pose: pose, orientation: orientation, kneeAngle: kneeAngle)
  }

  /// セッションを終了し，サマリーを生成する
  func finishSession(at endTime: TimeInterval) -> WorkoutSummary {
    var faultCounts = faultDebouncer.faultCounts
    if shallowRepCount > 0 {
      faultCounts[.shallowDepth, default: 0] += shallowRepCount
    }
    let summary = WorkoutSummary(
      totalReps: repCounter.repCount,
      averageBPM: tempoAnalyzer.bpm,
      faultCounts: faultCounts,
      duration: endTime - (sessionStart ?? endTime),
      reps: repCounter.reps
    )
    reset()
    return summary
  }

  /// 全状態をリセットする
  func reset() {
    repCounter.reset()
    tempoAnalyzer.reset()
    orientationSmoother.reset()
    faultDebouncer.reset()
    sessionStart = nil
    shallowRepCount = 0
  }

  /// 現在の状態からWorkoutUpdateを組み立てる
  private func makeUpdate(
    pose: BodyPose?,
    orientation: BodyOrientation,
    kneeAngle: Double?
  ) -> WorkoutUpdate {
    WorkoutUpdate(
      pose: pose,
      orientation: orientation,
      phase: repCounter.phase,
      repCount: repCounter.repCount,
      bpm: tempoAnalyzer.bpm,
      activeFaults: faultDebouncer.activeFaults,
      kneeAngle: kneeAngle
    )
  }
}
