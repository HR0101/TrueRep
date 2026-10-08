//
//  WorkoutView.swift
//  TrueRep
//
//  トレーニング中のライブ画面（カメラ＋骨格オーバーレイ＋HUD）
//

import SwiftUI
import UIKit

/// トレーニングのライブ画面
///
/// トレーニング中は画面を注視できないため，テキスト情報は最小限にし，
/// 色の変化と大きなタイポグラフィのみで状態を伝える
struct WorkoutView: View {

  /// セッションのViewModel
  @Bindable var viewModel: WorkoutViewModel
  /// 画面を閉じるためのコールバック
  let onFinish: () -> Void

  var body: some View {
    ZStack {
      Color.backgroundDark.ignoresSafeArea()

      switch viewModel.state {
      case .running:
        liveContent
      case .starting:
        ProgressView()
          .tint(.neonGreen)
          .scaleEffect(1.5)
      case .permissionDenied:
        permissionDeniedContent
      case .failed(let message):
        errorContent(message: message)
      case .idle:
        Color.clear
      }
    }
    .preferredColorScheme(.dark)
  }

  // MARK: - ライブ表示

  /// カメラ・骨格・HUDを重ねたメインコンテンツ
  private var liveContent: some View {
    ZStack {
      // カメラプレビュー（最背面）
      CameraPreviewView(session: viewModel.captureSession)
        .ignoresSafeArea()

      // 骨格オーバーレイ
      SkeletonOverlayView(
        pose: viewModel.currentPose,
        isFormGood: viewModel.isFormGood
      )
      .ignoresSafeArea()

      // フォーム警告の縁取り（画面端が赤く光る．注視せず気づける）
      if !viewModel.isFormGood {
        RoundedRectangle(cornerRadius: 0)
          .strokeBorder(Color.alertRed.opacity(0.8), lineWidth: 8)
          .ignoresSafeArea()
          .transition(.opacity)
      }

      // HUD（前面）
      VStack {
        topBar
        Spacer()
        faultBanner
        MetricsHUDView(
          repCount: viewModel.repCount,
          bpm: viewModel.bpm,
          phase: viewModel.phase
        )
      }
      .padding()
    }
    .animation(.easeInOut(duration: 0.2), value: viewModel.isFormGood)
  }

  /// 上部バー（向き表示・カメラ切替・終了ボタン）
  private var topBar: some View {
    HStack {
      // 検出中の身体の向き
      Label(viewModel.orientation.label, systemImage: "person.fill.viewfinder")
        .font(.subheadline.bold())
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())

      Spacer()

      // カメラ切替
      Button {
        viewModel.switchCamera()
      } label: {
        Image(systemName: "arrow.triangle.2.circlepath.camera")
          .font(.title3.bold())
          .foregroundStyle(.white)
          .padding(10)
          .background(.black.opacity(0.5), in: Circle())
      }

      // 終了ボタン
      Button {
        onFinish()
      } label: {
        Image(systemName: "xmark")
          .font(.title3.bold())
          .foregroundStyle(.white)
          .padding(10)
          .background(Color.alertRed.opacity(0.8), in: Circle())
      }
    }
  }

  /// フォーム警告バナー（最小限の大きな文字で表示する）
  @ViewBuilder
  private var faultBanner: some View {
    if let fault = viewModel.activeFaults.first {
      Text(fault.message)
        .font(.system(size: 32, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.alertRed.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .transition(.scale.combined(with: .opacity))
        .padding(.bottom, 8)
    }
  }

  // MARK: - 権限・エラー表示

  /// カメラ権限がない場合の案内
  private var permissionDeniedContent: some View {
    VStack(spacing: 16) {
      Image(systemName: "video.slash.fill")
        .font(.system(size: 48))
        .foregroundStyle(.alertRed)
      Text("カメラへのアクセスが必要です")
        .font(.title3.bold())
        .foregroundStyle(.white)
      Text("設定アプリからカメラの使用を許可してください")
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.6))
      Button("設定を開く") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(.neonGreen)
      Button("閉じる", action: onFinish)
        .foregroundStyle(.white.opacity(0.6))
    }
    .padding()
  }

  /// エラー発生時の表示
  private func errorContent(message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.alertRed)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.8))
        .multilineTextAlignment(.center)
      Button("閉じる", action: onFinish)
        .buttonStyle(.borderedProminent)
        .tint(.neonGreen)
    }
    .padding()
  }
}

/// 下部のメトリクスHUD（レップ数・BPM・動作状態）
struct MetricsHUDView: View {

  /// 有効レップ数
  let repCount: Int
  /// 現在のBPM
  let bpm: Double?
  /// 現在のレップ動作の状態
  let phase: RepPhase

  var body: some View {
    HStack(spacing: 32) {
      // レップ数（最重要情報なので最も大きく表示する）
      VStack(spacing: 0) {
        Text("\(repCount)")
          .font(.system(size: 72, weight: .black, design: .rounded))
          .foregroundStyle(.neonGreen)
          .contentTransition(.numericText())
          .animation(.snappy, value: repCount)
        Text("REPS")
          .font(.caption.bold())
          .foregroundStyle(.white.opacity(0.5))
      }

      // BPM
      VStack(spacing: 0) {
        Text(bpm.map { String(format: "%.0f", $0) } ?? "–")
          .font(.system(size: 48, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
        Text("BPM")
          .font(.caption.bold())
          .foregroundStyle(.white.opacity(0.5))
      }

      // 動作状態インジケーター（下降・上昇を矢印で示す）
      phaseIndicator
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 16)
    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
  }

  /// 動作状態を矢印アイコンで表示する
  private var phaseIndicator: some View {
    let (symbol, color): (String, Color) = {
      switch phase {
      case .standing: return ("figure.stand", .white.opacity(0.5))
      case .descending: return ("arrow.down", .neonGreen)
      case .bottom: return ("minus", .yellow)
      case .ascending: return ("arrow.up", .neonGreen)
      }
    }()
    return Image(systemName: symbol)
      .font(.system(size: 36, weight: .bold))
      .foregroundStyle(color)
      .frame(width: 48)
      .animation(.easeInOut(duration: 0.15), value: phase)
  }
}
