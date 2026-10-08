//
//  CameraManager.swift
//  TrueRep
//
//  カメラキャプチャ管理（専用シリアルキューで動作するパイプライン第1段）
//

import Foundation
import AVFoundation

/// カメラ関連のエラー
nonisolated enum CameraError: Error, LocalizedError {
  /// カメラへのアクセスが許可されていない
  case permissionDenied
  /// カメラデバイスが見つからない
  case deviceUnavailable
  /// セッションの構成に失敗した
  case configurationFailed

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "カメラへのアクセスが許可されていません．設定アプリから許可してください．"
    case .deviceUnavailable:
      return "カメラデバイスが見つかりません．"
    case .configurationFailed:
      return "カメラの初期化に失敗しました．"
    }
  }
}

/// カメラキャプチャの管理クラス
///
/// セッションの構成・開始・停止はすべて専用シリアルキュー（sessionQueue）上で行い，
/// フレームの受信は別のシリアルキュー（captureQueue）上で行う．
/// UIスレッドをブロックしないパイプライン分離の第1段を担う．
nonisolated final class CameraManager: NSObject, @unchecked Sendable {

  /// キャプチャセッション（プレビューレイヤーから参照される）
  let session = AVCaptureSession()

  /// セッション操作専用のシリアルキュー
  private let sessionQueue = DispatchQueue(label: "com.truerep.camera.session")
  /// フレーム受信専用のシリアルキュー
  private let captureQueue = DispatchQueue(label: "com.truerep.camera.capture")

  /// 映像出力
  private let videoOutput = AVCaptureVideoDataOutput()
  /// 現在のカメラ位置
  private(set) var position: AVCaptureDevice.Position = .front

  /// フレーム受信時のハンドラー（captureQueue上で呼ばれる）
  /// - Note: CVPixelBufferの所有権はハンドラー内でのみ有効．保持しないこと
  var frameHandler: (@Sendable (CVPixelBuffer, TimeInterval) -> Void)?

  /// カメラ権限を確認し，必要なら要求する
  static func requestPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default:
      return false
    }
  }

  /// セッションを構成して開始する
  func start(position: AVCaptureDevice.Position = .front) async throws {
    self.position = position
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      sessionQueue.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: CameraError.configurationFailed)
          return
        }
        do {
          try self.configureSession(position: position)
          self.session.startRunning()
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// セッションを停止する
  func stop() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  /// 前面／背面カメラを切り替える
  func switchCamera() {
    let newPosition: AVCaptureDevice.Position = (position == .front) ? .back : .front
    position = newPosition
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.session.beginConfiguration()
      // 既存の入力をすべて取り除いてから新しいカメラを追加する
      for input in self.session.inputs {
        self.session.removeInput(input)
      }
      try? self.addCameraInput(position: newPosition)
      self.updateConnectionSettings(position: newPosition)
      self.session.commitConfiguration()
    }
  }

  // MARK: - プライベート（sessionQueue上で実行）

  /// セッションを構成する
  private func configureSession(position: AVCaptureDevice.Position) throws {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    // メモリ消費を抑えるため720pを使用する（姿勢推定には十分な解像度）
    if session.canSetSessionPreset(.hd1280x720) {
      session.sessionPreset = .hd1280x720
    }

    for input in session.inputs {
      session.removeInput(input)
    }
    try addCameraInput(position: position)

    if !session.outputs.contains(videoOutput) {
      // 推論が追いつかないフレームは破棄してメモリ滞留を防ぐ
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      ]
      videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
      guard session.canAddOutput(videoOutput) else {
        throw CameraError.configurationFailed
      }
      session.addOutput(videoOutput)
    }

    updateConnectionSettings(position: position)
  }

  /// カメラ入力を追加する
  private func addCameraInput(position: AVCaptureDevice.Position) throws {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
      throw CameraError.deviceUnavailable
    }
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      throw CameraError.configurationFailed
    }
    session.addInput(input)
  }

  /// 出力コネクションの向き・ミラーリングを設定する
  ///
  /// フロントカメラのプレビューは自動で鏡像になるため，
  /// バッファ側もミラーリングして骨格オーバーレイの座標を一致させる
  private func updateConnectionSettings(position: AVCaptureDevice.Position) {
    guard let connection = videoOutput.connection(with: .video) else { return }
    // 縦持ち前提でバッファを正立させる（Vision推論の精度安定のため）
    if connection.isVideoRotationAngleSupported(90) {
      connection.videoRotationAngle = 90
    }
    if connection.isVideoMirroringSupported {
      connection.isVideoMirrored = (position == .front)
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

// デリゲートはcaptureQueue（バックグラウンド）から呼ばれるため，準拠をnonisolatedで宣言する
extension CameraManager: nonisolated AVCaptureVideoDataOutputSampleBufferDelegate {

  /// フレーム受信（captureQueue上で呼ばれる）
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    frameHandler?(pixelBuffer, timestamp)
  }
}
