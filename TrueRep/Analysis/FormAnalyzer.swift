//
//  FormAnalyzer.swift
//  TrueRep
//
//  身体の向きに応じたフォーム判定（どのアングルからでも使えるよう自動切替する）
//

import Foundation

/// フォームの問題を検知する
///
/// 撮影アングルに依存しないよう，向き（正面／側面／斜め）ごとに
/// 適用可能な判定ルールを自動で切り替える．
/// - 正面: 膝の内入り（ニーイン），左右バランス
/// - 側面: 体幹の過度な前傾
/// - 全アングル共通: しゃがみの深さ（レップ完了時に判定）
nonisolated enum FormAnalyzer {

  /// 判定しきい値
  nonisolated enum Threshold {
    /// ニーイン判定: 膝間距離÷足首間距離がこの値未満なら膝が内側に入っている
    static let kneeValgusRatio: Double = 0.75
    /// 左右バランス判定: 腰中点の左右ズレ（足首間距離に対する比率）の上限
    static let lateralOffsetRatio: Double = 0.35
    /// 過前傾判定: 体幹の鉛直からの傾き（度）の上限
    static let maxTorsoLean: Double = 65
  }

  /// 現在のフレームのフォーム問題を検知する
  /// - Parameters:
  ///   - pose: 姿勢検出結果
  ///   - orientation: 身体の向き
  ///   - phase: レップ動作の状態
  /// - Returns: 検知された問題の集合（空なら良好）
  static func analyze(
    pose: BodyPose,
    orientation: BodyOrientation,
    phase: RepPhase
  ) -> Set<FormFault> {
    var faults: Set<FormFault> = []

    // フォーム判定は動作中（下降〜上昇）のみ行う．立位での誤検知を防ぐ
    let isMoving = phase != .standing

    switch orientation {
    case .front:
      if isMoving {
        if detectKneeValgus(pose: pose) {
          faults.insert(.kneeValgus)
        }
        if detectLateralImbalance(pose: pose) {
          faults.insert(.lateralImbalance)
        }
      }
    case .side, .oblique:
      // 側面・斜めでは体幹の前傾のみ判定する（膝の左右関係は遠近で歪むため）
      if isMoving, detectExcessiveLean(pose: pose) {
        faults.insert(.excessiveLean)
      }
    case .unknown:
      break
    }

    return faults
  }

  /// 膝の内入り（ニーイン）を検知する（正面視）
  ///
  /// 膝間の水平距離が足首間の水平距離より大きく狭まっている場合をニーインとみなす
  private static func detectKneeValgus(pose: BodyPose) -> Bool {
    guard
      let leftKnee = pose[.leftKnee], let rightKnee = pose[.rightKnee],
      let leftAnkle = pose[.leftAnkle], let rightAnkle = pose[.rightAnkle]
    else { return false }

    let kneeDistance = abs(leftKnee.position.x - rightKnee.position.x)
    let ankleDistance = abs(leftAnkle.position.x - rightAnkle.position.x)
    // 足首がほぼ重なって見える場合は判定しない（誤検知防止）
    guard ankleDistance > 0.03 else { return false }

    return kneeDistance / ankleDistance < Threshold.kneeValgusRatio
  }

  /// 左右バランスの崩れを検知する（正面視）
  ///
  /// 腰の中点が足首間の中心から大きく左右にズレている場合を崩れとみなす
  private static func detectLateralImbalance(pose: BodyPose) -> Bool {
    guard
      let hipCenter = pose.hipCenter,
      let leftAnkle = pose[.leftAnkle], let rightAnkle = pose[.rightAnkle]
    else { return false }

    let ankleCenterX = (leftAnkle.position.x + rightAnkle.position.x) / 2
    let ankleDistance = abs(leftAnkle.position.x - rightAnkle.position.x)
    guard ankleDistance > 0.03 else { return false }

    let offset = abs(hipCenter.x - ankleCenterX)
    return offset / ankleDistance > Threshold.lateralOffsetRatio
  }

  /// 体幹の過度な前傾を検知する（側面視）
  ///
  /// 背中の丸まりは関節点のみでは直接計測できないため，
  /// 体幹の傾きが過大な場合を前傾しすぎ（丸まりの兆候）として警告する
  private static func detectExcessiveLean(pose: BodyPose) -> Bool {
    guard let lean = AngleCalculator.torsoLeanAngle(of: pose) else { return false }
    return lean > Threshold.maxTorsoLean
  }
}

/// フォーム警告のチラつき防止（一定フレーム連続で検知された場合のみ表示する）
nonisolated struct FaultDebouncer: Sendable {
  /// 警告を表示するまでの連続検知回数
  private static let activationCount = 3
  /// 警告を解除するまでの連続非検知回数
  private static let deactivationCount = 5

  /// 問題ごとの連続検知カウント
  private var detectionCounts: [FormFault: Int] = [:]
  /// 問題ごとの連続非検知カウント
  private var clearCounts: [FormFault: Int] = [:]
  /// 現在アクティブな警告
  private(set) var activeFaults: Set<FormFault> = []
  /// セッション中の警告発生回数（種類別，サマリー用）
  private(set) var faultCounts: [FormFault: Int] = [:]

  /// 新しいフレームの検知結果を取り込み，アクティブな警告を更新する
  mutating func update(with detected: Set<FormFault>) -> Set<FormFault> {
    for fault in FormFault.allCases {
      if detected.contains(fault) {
        detectionCounts[fault, default: 0] += 1
        clearCounts[fault] = 0
        // 連続検知がしきい値に達したら警告をアクティブにする
        if detectionCounts[fault, default: 0] >= Self.activationCount,
           !activeFaults.contains(fault) {
          activeFaults.insert(fault)
          faultCounts[fault, default: 0] += 1
        }
      } else {
        clearCounts[fault, default: 0] += 1
        detectionCounts[fault] = 0
        // 連続非検知がしきい値に達したら警告を解除する
        if clearCounts[fault, default: 0] >= Self.deactivationCount {
          activeFaults.remove(fault)
        }
      }
    }
    return activeFaults
  }

  /// 状態をリセットする
  mutating func reset() {
    detectionCounts.removeAll()
    clearCounts.removeAll()
    activeFaults.removeAll()
    faultCounts.removeAll()
  }
}
