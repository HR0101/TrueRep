//
//  AnalysisLogicTests.swift
//  TrueRepTests
//
//  解析ロジック（角度計算・レップカウント・BPM・フォーム判定）のユニットテスト
//

import Testing
import Foundation
import CoreGraphics
@testable import TrueRep

// MARK: - テスト用ヘルパー

/// テスト用の姿勢データを生成する
private func makePose(
  joints: [JointName: CGPoint],
  timestamp: TimeInterval = 0,
  confidence: Float = 0.9
) -> BodyPose {
  var dict: [JointName: Joint] = [:]
  for (name, point) in joints {
    dict[name] = Joint(name: name, position: point, confidence: confidence)
  }
  return BodyPose(joints: dict, timestamp: timestamp)
}

/// 正面向きの姿勢（スクワット深度を指定可能）を生成する
///
/// - Parameter depth: 0=直立，1=フルスクワット．腰と肩の座標を深度に応じて下げる
private func makeFrontSquatPose(
  depth: Double,
  timestamp: TimeInterval,
  kneeInset: Double = 0
) -> BodyPose {
  // 直立時: 腰y=0.5，膝y=0.3，足首y=0.1．しゃがむと腰が下がる
  let hipY = 0.5 - 0.18 * depth
  let kneeX = 0.08 - kneeInset
  return makePose(
    joints: [
      .leftShoulder: CGPoint(x: 0.38, y: 0.75 - 0.18 * depth),
      .rightShoulder: CGPoint(x: 0.62, y: 0.75 - 0.18 * depth),
      .leftHip: CGPoint(x: 0.45, y: hipY),
      .rightHip: CGPoint(x: 0.55, y: hipY),
      .root: CGPoint(x: 0.5, y: hipY),
      .leftKnee: CGPoint(x: 0.5 - kneeX, y: 0.3),
      .rightKnee: CGPoint(x: 0.5 + kneeX, y: 0.3),
      .leftAnkle: CGPoint(x: 0.42, y: 0.1),
      .rightAnkle: CGPoint(x: 0.58, y: 0.1),
    ],
    timestamp: timestamp
  )
}

// MARK: - 角度計算のテスト

struct AngleCalculatorTests {

  @Test("直角の3点から90度が計算される")
  func rightAngle() {
    let angle = AngleCalculator.angle(
      at: CGPoint(x: 0, y: 0),
      from: CGPoint(x: 1, y: 0),
      to: CGPoint(x: 0, y: 1)
    )
    #expect(angle != nil)
    #expect(abs(angle! - 90) < 0.001)
  }

  @Test("一直線の3点から180度が計算される")
  func straightLine() {
    let angle = AngleCalculator.angle(
      at: CGPoint(x: 0.5, y: 0.5),
      from: CGPoint(x: 0, y: 0.5),
      to: CGPoint(x: 1, y: 0.5)
    )
    #expect(angle != nil)
    #expect(abs(angle! - 180) < 0.001)
  }

  @Test("頂点と同一の点を渡すとnilが返る")
  func degenerateCase() {
    let angle = AngleCalculator.angle(
      at: CGPoint(x: 0.5, y: 0.5),
      from: CGPoint(x: 0.5, y: 0.5),
      to: CGPoint(x: 1, y: 1)
    )
    #expect(angle == nil)
  }

  @Test("直立姿勢の体幹の傾きはほぼ0度になる")
  func uprightTorso() {
    let pose = makeFrontSquatPose(depth: 0, timestamp: 0)
    let lean = AngleCalculator.torsoLeanAngle(of: pose)
    #expect(lean != nil)
    #expect(abs(lean!) < 1.0)
  }
}

// MARK: - 向き判定のテスト

struct OrientationDetectorTests {

  @Test("肩幅が広い姿勢は正面と判定される")
  func frontDetection() {
    let pose = makeFrontSquatPose(depth: 0, timestamp: 0)
    #expect(OrientationDetector.detect(from: pose) == .front)
  }

  @Test("肩がほぼ重なる姿勢は側面と判定される")
  func sideDetection() {
    let pose = makePose(joints: [
      .leftShoulder: CGPoint(x: 0.50, y: 0.75),
      .rightShoulder: CGPoint(x: 0.52, y: 0.75),
      .leftHip: CGPoint(x: 0.50, y: 0.5),
      .rightHip: CGPoint(x: 0.51, y: 0.5),
    ])
    #expect(OrientationDetector.detect(from: pose) == .side)
  }

  @Test("関節が検出できない場合はunknownになる")
  func unknownDetection() {
    let pose = makePose(joints: [:])
    #expect(OrientationDetector.detect(from: pose) == .unknown)
  }
}

// MARK: - レップカウントのテスト

struct RepCounterTests {

  /// スクワット1サイクル分の腰Y座標を時系列でカウンターに流す
  ///
  /// sin波で下降→上昇を表現し，最後に立位での静止フレームを加えて
  /// 立位復帰の判定を確実に完了させる
  private func performRep(
    counter: inout RepCounter,
    startTime: TimeInterval,
    repDuration: TimeInterval = 2.0,
    depth: Double = 1.0,
    kneeAngleAtBottom: Double = 80
  ) -> RepRecord? {
    var completed: RepRecord?
    let steps = 30
    for i in 0...steps {
      let progress = Double(i) / Double(steps)
      // sin波で下降→上昇を表現する（0→depth→0）
      let currentDepth = depth * sin(progress * .pi)
      let hipY = 0.5 - 0.18 * currentDepth
      // 膝角度は深度に比例して浅くなる（直立170度→ボトムで指定角度）
      let kneeAngle = 170 - (170 - kneeAngleAtBottom) * currentDepth
      let record = counter.process(
        hipY: hipY,
        kneeAngle: kneeAngle,
        torso: 0.25,
        timestamp: startTime + progress * repDuration
      )
      if let record { completed = record }
    }
    // 立位での静止フレーム（平滑化の遅れを吸収して立位復帰を完了させる）
    for i in 0..<8 {
      let record = counter.process(
        hipY: 0.5,
        kneeAngle: 170,
        torso: 0.25,
        timestamp: startTime + repDuration + Double(i + 1) * 0.07
      )
      if let record { completed = record }
    }
    return completed
  }

  @Test("深いスクワット3回が3レップとしてカウントされる")
  func countsValidReps() {
    var counter = RepCounter()
    // 立位で基準を安定させる
    for i in 0..<10 {
      _ = counter.process(hipY: 0.5, kneeAngle: 170, torso: 0.25, timestamp: Double(i) * 0.07)
    }
    for rep in 0..<3 {
      _ = performRep(counter: &counter, startTime: 1.0 + Double(rep) * 3.0)
    }
    #expect(counter.repCount == 3)
  }

  @Test("浅いスクワットは有効レップとしてカウントされない")
  func rejectsShallowReps() {
    var counter = RepCounter()
    for i in 0..<10 {
      _ = counter.process(hipY: 0.5, kneeAngle: 170, torso: 0.25, timestamp: Double(i) * 0.07)
    }
    // 膝角度140度までしか曲げない浅いスクワット（下降自体は検知される深さ）
    let record = performRep(
      counter: &counter,
      startTime: 1.0,
      depth: 0.5,
      kneeAngleAtBottom: 140
    )
    #expect(counter.repCount == 0)
    // レップ自体は完了として検知されるがROM未達になる
    if let record {
      #expect(record.metDepth == false)
    }
  }

  @Test("レップ完了時の所要時間がおおむね正しい")
  func repDurationIsReasonable() {
    var counter = RepCounter()
    for i in 0..<10 {
      _ = counter.process(hipY: 0.5, kneeAngle: 170, torso: 0.25, timestamp: Double(i) * 0.07)
    }
    let record = performRep(counter: &counter, startTime: 1.0, repDuration: 2.0)
    #expect(record != nil)
    if let record {
      // 下降開始の検知遅れ・静止フレームでの完了を考慮した範囲で確認する
      #expect(record.duration > 0.8)
      #expect(record.duration < 3.0)
    }
  }
}

// MARK: - BPM算出のテスト

struct TempoAnalyzerTests {

  @Test("2秒のレップが続くとBPMは30になる")
  func bpmCalculation() {
    var analyzer = TempoAnalyzer()
    analyzer.add(duration: 2.0)
    analyzer.add(duration: 2.0)
    analyzer.add(duration: 2.0)
    #expect(analyzer.bpm != nil)
    #expect(abs(analyzer.bpm! - 30) < 0.001)
  }

  @Test("レップがない場合のBPMはnil")
  func emptyBPM() {
    let analyzer = TempoAnalyzer()
    #expect(analyzer.bpm == nil)
  }

  @Test("直近のレップのみがBPMに反映される（ウィンドウ方式）")
  func slidingWindow() {
    var analyzer = TempoAnalyzer()
    // 古い遅いレップ（窓から押し出される）
    analyzer.add(duration: 10.0)
    // 直近4回は2秒
    for _ in 0..<4 {
      analyzer.add(duration: 2.0)
    }
    #expect(abs(analyzer.bpm! - 30) < 0.001)
  }
}

// MARK: - フォーム判定のテスト

struct FormAnalyzerTests {

  @Test("膝が内側に入った姿勢でニーインが検知される")
  func detectsKneeValgus() {
    // 膝間距離を足首間距離より大幅に狭くする
    let pose = makeFrontSquatPose(depth: 0.8, timestamp: 0, kneeInset: 0.05)
    let faults = FormAnalyzer.analyze(pose: pose, orientation: .front, phase: .descending)
    #expect(faults.contains(.kneeValgus))
  }

  @Test("正常なフォームでは警告が出ない")
  func cleanFormHasNoFaults() {
    let pose = makeFrontSquatPose(depth: 0.8, timestamp: 0)
    let faults = FormAnalyzer.analyze(pose: pose, orientation: .front, phase: .descending)
    #expect(faults.isEmpty)
  }

  @Test("立位ではフォーム判定を行わない")
  func noFaultsWhileStanding() {
    let pose = makeFrontSquatPose(depth: 0, timestamp: 0, kneeInset: 0.05)
    let faults = FormAnalyzer.analyze(pose: pose, orientation: .front, phase: .standing)
    #expect(faults.isEmpty)
  }

  @Test("側面視では体幹の過前傾が検知される")
  func detectsExcessiveLean() {
    // 肩が腰よりも大きく前（X方向）に出た前傾姿勢
    let pose = makePose(joints: [
      .leftShoulder: CGPoint(x: 0.70, y: 0.55),
      .rightShoulder: CGPoint(x: 0.71, y: 0.55),
      .leftHip: CGPoint(x: 0.45, y: 0.45),
      .rightHip: CGPoint(x: 0.46, y: 0.45),
    ])
    let faults = FormAnalyzer.analyze(pose: pose, orientation: .side, phase: .descending)
    #expect(faults.contains(.excessiveLean))
  }

  @Test("警告のデバウンスは連続検知後にのみアクティブになる")
  func debouncerActivation() {
    var debouncer = FaultDebouncer()
    // 2回連続ではまだアクティブにならない
    _ = debouncer.update(with: [.kneeValgus])
    let after2 = debouncer.update(with: [.kneeValgus])
    #expect(!after2.contains(.kneeValgus))
    // 3回目でアクティブになる
    let after3 = debouncer.update(with: [.kneeValgus])
    #expect(after3.contains(.kneeValgus))
    // 発生回数は1回として記録される
    #expect(debouncer.faultCounts[.kneeValgus] == 1)
  }
}
