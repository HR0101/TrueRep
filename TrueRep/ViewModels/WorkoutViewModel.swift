//
//  WorkoutViewModel.swift
//  TrueRep
//
//  トレーニングセッションの状態管理（メインスレッドで動作するパイプライン第3段）
//

import Foundation
import Observation
import AVFoundation

/// セッションの画面状態
enum SessionState: Equatable {
  /// 開始前
  case idle
  /// カメラ権限がない
  case permissionDenied
  /// カメラ起動中
  case starting
  /// トレーニング中
  case running
  /// エラー発生
  case failed(String)
}

/// トレーニングセッションのViewModel
///
/// カメラ→推論→解析の結果ストリームをメインスレッドで受け取り，
/// SwiftUIへ公開する．重い処理は一切行わず，状態の反映のみを担当する
@Observable
final class WorkoutViewModel {

  // MARK: - UIへ公開する状態

  /// 画面状態
  private(set) var state: SessionState = .idle
  /// 最新の姿勢（骨格オーバーレイ描画用）
  private(set) var currentPose: BodyPose?
  /// 有効レップ数
  private(set) var repCount = 0
  /// 現在のBPM
  private(set) var bpm: Double?
  /// 現在のレップ動作の状態
  private(set) var phase: RepPhase = .standing
  /// 身体の向き
  private(set) var orientation: BodyOrientation = .unknown
  /// アクティブなフォーム警告
  private(set) var activeFaults: Set<FormFault> = []
  /// 現在の膝角度
  private(set) var kneeAngle: Double?
  /// セッション終了後のサマリー（非nilでサマリー画面を表示する）
  var summary: WorkoutSummary?

  /// フォームが良好か（オーバーレイの色分けに使用）
  var isFormGood: Bool { activeFaults.isEmpty }

  /// プレビュー表示用のキャプチャセッション
  var captureSession: AVCaptureSession { cameraManager.session }

  // MARK: - パイプライン構成要素

  /// カメラ管理（第1段: キャプチャ専用キュー）
  private let cameraManager = CameraManager()
  /// 姿勢推定器（第2段: 推論専用キュー）
  /// - Note: AsyncStreamは一度終了すると再利用できないため，セッションごとに作り直す
  private var poseEstimator = PoseEstimator()
  /// 解析エンジン（第2.5段: actor）
  private let analysisEngine = AnalysisEngine()
  /// 結果ストリームの消費タスク
  private var consumeTask: Task<Void, Never>?

  // MARK: - セッション制御

  /// セッションを開始する
  func start() async {
    guard state == .idle || state == .permissionDenied else { return }
    state = .starting

    // カメラ権限の確認
    guard await CameraManager.requestPermission() else {
      state = .permissionDenied
      return
    }

    // 推定器をセッションごとに作り直し，カメラのフレームを接続する（captureQueue上で呼ばれる）
    poseEstimator = PoseEstimator()
    let estimator = poseEstimator
    cameraManager.frameHandler = { pixelBuffer, timestamp in
      estimator.submit(pixelBuffer: pixelBuffer, timestamp: timestamp)
    }

    do {
      try await cameraManager.start(position: .front)
    } catch {
      state = .failed(error.localizedDescription)
      return
    }

    await analysisEngine.reset()
    state = .running

    // 推定結果ストリームの消費を開始する
    consumeTask = Task { [weak self] in
      guard let self else { return }
      for await pose in self.poseEstimator.poses {
        guard !Task.isCancelled else { break }
        let update = await self.analysisEngine.process(pose: pose)
        self.apply(update)
      }
    }
  }

  /// セッションを終了し，サマリーを生成する
  func finish() async {
    // 正常にトレーニング中だった場合のみサマリーを表示する
    let shouldShowSummary = (state == .running)

    consumeTask?.cancel()
    consumeTask = nil
    cameraManager.frameHandler = nil
    cameraManager.stop()

    let endTime = currentPose?.timestamp ?? Date().timeIntervalSince1970
    let result = await analysisEngine.finishSession(at: endTime)
    if shouldShowSummary {
      summary = result
    }
    state = .idle
    currentPose = nil
  }

  /// 前面／背面カメラを切り替える
  func switchCamera() {
    cameraManager.switchCamera()
  }

  // MARK: - プライベート

  /// 解析結果をUI状態へ反映する
  private func apply(_ update: WorkoutUpdate) {
    currentPose = update.pose
    repCount = update.repCount
    bpm = update.bpm
    phase = update.phase
    orientation = update.orientation
    activeFaults = update.activeFaults
    kneeAngle = update.kneeAngle
  }
}
