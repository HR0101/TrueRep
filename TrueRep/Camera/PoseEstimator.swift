//
//  PoseEstimator.swift
//  TrueRep
//
//  Visionによる姿勢推定（バックグラウンドキューで動作するパイプライン第2段）
//

import Foundation
import Vision
import CoreVideo

/// 姿勢推定器
///
/// カメラキューから受け取ったフレームを推論専用キューで処理し，
/// Sendableな BodyPose に変換して AsyncStream で下流へ流す．
/// - フレーム間引き: 推論は目標fps（既定15fps）まで間引き，それ以外は即破棄する
/// - ビジードロップ: 推論中に届いたフレームは破棄し，遅延の蓄積を防ぐ
/// - サーマル対策: 端末の熱状態に応じて目標fpsを自動的に下げる
nonisolated final class PoseEstimator: @unchecked Sendable {

  /// 通常時の推論間隔（秒）= 15fps
  private static let normalInterval: TimeInterval = 1.0 / 15.0
  /// 熱状態が深刻なときの推論間隔（秒）= 8fps
  private static let seriousInterval: TimeInterval = 1.0 / 8.0
  /// 熱状態が危機的なときの推論間隔（秒）= 4fps
  private static let criticalInterval: TimeInterval = 1.0 / 4.0

  /// 推論専用のシリアルキュー（カメラキューとは分離する）
  private let inferenceQueue = DispatchQueue(label: "com.truerep.inference", qos: .userInitiated)

  /// Visionリクエスト（毎フレーム生成せず再利用してオーバーヘッドを抑える）
  private let request = VNDetectHumanBodyPoseRequest()

  /// 状態保護用のロック（captureQueueとinferenceQueueの両方から触るため）
  private let lock = NSLock()
  /// 推論中フラグ（ビジードロップ用）
  private var isProcessing = false
  /// 最後に推論したフレームの時刻（間引き用）
  private var lastInferenceTime: TimeInterval = 0
  /// 現在の推論間隔（サーマル状態で変動する）
  private var inferenceInterval: TimeInterval = PoseEstimator.normalInterval

  /// 推定結果のストリーム（最新1件のみバッファし，古い結果は自動破棄する）
  let poses: AsyncStream<BodyPose>
  /// ストリームへの送出口
  private let continuation: AsyncStream<BodyPose>.Continuation

  /// サーマル状態変化の監視トークン
  private var thermalObserver: NSObjectProtocol?

  init() {
    // UIが消費しきれない場合は最新の結果だけを残す（遅延の蓄積防止）
    let (stream, streamContinuation) = AsyncStream.makeStream(
      of: BodyPose.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    poses = stream
    continuation = streamContinuation

    // 端末の熱状態に応じて推論レートを動的に調整する
    thermalObserver = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.updateThermalThrottling()
    }
    updateThermalThrottling()
  }

  deinit {
    if let observer = thermalObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    continuation.finish()
  }

  /// フレームを推論に投入する（captureQueue上から呼ばれる）
  ///
  /// 間引き対象または推論中の場合はフレームを即座に破棄して戻る．
  /// CVPixelBufferは推論キューに渡す間ARCで保持される
  func submit(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
    lock.lock()
    // 間引き判定: 前回の推論から十分な時間が経過していなければ破棄する
    guard timestamp - lastInferenceTime >= inferenceInterval, !isProcessing else {
      lock.unlock()
      return
    }
    isProcessing = true
    lastInferenceTime = timestamp
    lock.unlock()

    // CVPixelBufferはSendableではないが，このフレームの所有権は以降推論キューのみが持つ
    // （captureQueue側はこの後バッファに触れない）ため安全に受け渡せる
    nonisolated(unsafe) let transferredBuffer = pixelBuffer
    inferenceQueue.async { [weak self] in
      guard let self else { return }
      defer {
        self.lock.lock()
        self.isProcessing = false
        self.lock.unlock()
      }
      self.performInference(on: transferredBuffer, timestamp: timestamp)
    }
  }

  /// Vision推論を実行し，結果をストリームへ流す（inferenceQueue上で実行）
  private func performInference(on pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
    do {
      try handler.perform([request])
      guard let observation = request.results?.first else {
        // 人体が検出されなかった場合は空の姿勢を流す（UI側で骨格を消すため）
        continuation.yield(BodyPose(joints: [:], timestamp: timestamp))
        return
      }
      let pose = Self.convert(observation: observation, timestamp: timestamp)
      continuation.yield(pose)
    } catch {
      // 推論失敗はフレーム落ちとして扱う（次フレームで回復するため何もしない）
    }
  }

  /// 熱状態に応じて推論間隔を更新する
  private func updateThermalThrottling() {
    let interval: TimeInterval
    switch ProcessInfo.processInfo.thermalState {
    case .nominal, .fair:
      interval = Self.normalInterval
    case .serious:
      interval = Self.seriousInterval
    case .critical:
      interval = Self.criticalInterval
    @unknown default:
      interval = Self.seriousInterval
    }
    lock.lock()
    inferenceInterval = interval
    lock.unlock()
  }

  /// VisionのObservationをSendableなBodyPoseへ変換する
  private static func convert(
    observation: VNHumanBodyPoseObservation,
    timestamp: TimeInterval
  ) -> BodyPose {
    /// Visionのジョイント名と内部のJointNameの対応表
    let mapping: [VNHumanBodyPoseObservation.JointName: JointName] = [
      .nose: .nose,
      .neck: .neck,
      .leftShoulder: .leftShoulder,
      .rightShoulder: .rightShoulder,
      .leftElbow: .leftElbow,
      .rightElbow: .rightElbow,
      .leftWrist: .leftWrist,
      .rightWrist: .rightWrist,
      .leftHip: .leftHip,
      .rightHip: .rightHip,
      .leftKnee: .leftKnee,
      .rightKnee: .rightKnee,
      .leftAnkle: .leftAnkle,
      .rightAnkle: .rightAnkle,
      .root: .root,
    ]

    var joints: [JointName: Joint] = [:]
    if let points = try? observation.recognizedPoints(.all) {
      for (visionName, name) in mapping {
        guard let point = points[visionName], point.confidence > 0 else { continue }
        joints[name] = Joint(
          name: name,
          position: CGPoint(x: point.location.x, y: point.location.y),
          confidence: point.confidence
        )
      }
    }
    return BodyPose(joints: joints, timestamp: timestamp)
  }
}
