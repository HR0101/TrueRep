//
//  AngleCalculator.swift
//  TrueRep
//
//  関節角度の計算（純粋関数のみ）
//

import Foundation
import CoreGraphics

/// 関節角度の計算ユーティリティ
nonisolated enum AngleCalculator {

  /// 3点A-B-Cが作る角度（頂点B）を度数法で返す
  /// - Returns: 0〜180度．ベクトルが零の場合はnil
  static func angle(at vertex: CGPoint, from pointA: CGPoint, to pointC: CGPoint) -> Double? {
    let v1 = CGVector(dx: pointA.x - vertex.x, dy: pointA.y - vertex.y)
    let v2 = CGVector(dx: pointC.x - vertex.x, dy: pointC.y - vertex.y)
    let len1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
    let len2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
    guard len1 > 0, len2 > 0 else { return nil }

    let dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2)
    // 浮動小数点誤差で[-1, 1]を超えないようにクランプする
    let clamped = max(-1.0, min(1.0, dot))
    return acos(clamped) * 180 / .pi
  }

  /// 膝の角度（股関節-膝-足首）を計算する．左右両方検出できた場合は平均を返す
  static func kneeAngle(of pose: BodyPose) -> Double? {
    var angles: [Double] = []

    if let hip = pose[.leftHip], let knee = pose[.leftKnee], let ankle = pose[.leftAnkle],
       let angle = angle(at: knee.position, from: hip.position, to: ankle.position) {
      angles.append(angle)
    }
    if let hip = pose[.rightHip], let knee = pose[.rightKnee], let ankle = pose[.rightAnkle],
       let angle = angle(at: knee.position, from: hip.position, to: ankle.position) {
      angles.append(angle)
    }

    guard !angles.isEmpty else { return nil }
    return angles.reduce(0, +) / Double(angles.count)
  }

  /// 体幹の鉛直からの傾き（度）を計算する．0度=直立，90度=水平
  static func torsoLeanAngle(of pose: BodyPose) -> Double? {
    guard let shoulder = pose.shoulderCenter, let hip = pose.hipCenter else { return nil }
    let dx = shoulder.x - hip.x
    let dy = shoulder.y - hip.y
    // 体幹がほぼ点に潰れている場合は判定不能
    let length = sqrt(dx * dx + dy * dy)
    guard length > 0.01 else { return nil }
    // 鉛直ベクトル(0, 1)との角度
    let cosValue = dy / length
    let clamped = max(-1.0, min(1.0, cosValue))
    return acos(clamped) * 180 / .pi
  }
}
