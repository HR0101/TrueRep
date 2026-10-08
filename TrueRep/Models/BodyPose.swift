//
//  BodyPose.swift
//  TrueRep
//
//  1フレーム分の姿勢推定結果を表すデータ構造
//

import Foundation
import CoreGraphics

/// 関節の種類（VisionのVNHumanBodyPoseObservationのジョイント名に対応）
nonisolated enum JointName: String, CaseIterable, Sendable {
  case nose
  case neck
  case leftShoulder
  case rightShoulder
  case leftElbow
  case rightElbow
  case leftWrist
  case rightWrist
  case leftHip
  case rightHip
  case leftKnee
  case rightKnee
  case leftAnkle
  case rightAnkle
  case root  // 腰の中心
}

/// 1つの関節の検出結果
nonisolated struct Joint: Sendable {
  /// 関節の種類
  let name: JointName
  /// 正規化座標（0〜1，原点は左下．Visionの座標系に準拠）
  let position: CGPoint
  /// 検出信頼度（0〜1）
  let confidence: Float
}

/// 1フレーム分の姿勢検出結果
nonisolated struct BodyPose: Sendable {
  /// 関節名をキーとした検出結果の辞書
  let joints: [JointName: Joint]
  /// フレームのタイムスタンプ（秒）
  let timestamp: TimeInterval

  /// 信頼度の下限（これ未満の関節は無効として扱う）
  static let minimumConfidence: Float = 0.3

  /// 指定した関節を取得する（信頼度が下限未満の場合はnil）
  subscript(name: JointName) -> Joint? {
    guard let joint = joints[name], joint.confidence >= Self.minimumConfidence else {
      return nil
    }
    return joint
  }

  /// 左右の腰の中点（両方検出できた場合のみ）
  var hipCenter: CGPoint? {
    if let root = self[.root] {
      return root.position
    }
    guard let left = self[.leftHip], let right = self[.rightHip] else { return nil }
    return CGPoint(
      x: (left.position.x + right.position.x) / 2,
      y: (left.position.y + right.position.y) / 2
    )
  }

  /// 左右の肩の中点（両方検出できた場合のみ）
  var shoulderCenter: CGPoint? {
    guard let left = self[.leftShoulder], let right = self[.rightShoulder] else { return nil }
    return CGPoint(
      x: (left.position.x + right.position.x) / 2,
      y: (left.position.y + right.position.y) / 2
    )
  }

  /// 全身の主要関節（腰・膝・足首）が検出できているか
  var hasLowerBody: Bool {
    hipCenter != nil
      && (self[.leftKnee] != nil || self[.rightKnee] != nil)
      && (self[.leftAnkle] != nil || self[.rightAnkle] != nil)
  }
}

/// 骨格描画用の接続定義（ボーン）
nonisolated enum SkeletonConnection {
  /// 関節同士の接続ペア一覧
  static let bones: [(JointName, JointName)] = [
    (.nose, .neck),
    (.neck, .leftShoulder),
    (.neck, .rightShoulder),
    (.leftShoulder, .leftElbow),
    (.leftElbow, .leftWrist),
    (.rightShoulder, .rightElbow),
    (.rightElbow, .rightWrist),
    (.neck, .root),
    (.root, .leftHip),
    (.root, .rightHip),
    (.leftHip, .leftKnee),
    (.leftKnee, .leftAnkle),
    (.rightHip, .rightKnee),
    (.rightKnee, .rightAnkle),
  ]
}
