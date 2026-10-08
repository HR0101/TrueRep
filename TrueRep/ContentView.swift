//
//  ContentView.swift
//  TrueRep
//
//  ルートビュー（ホーム→ワークアウト→サマリーの画面遷移を管理する）
//

import SwiftUI

struct ContentView: View {

  /// セッションのViewModel
  @State private var viewModel = WorkoutViewModel()
  /// ワークアウト画面を表示中か
  @State private var isWorkoutActive = false

  var body: some View {
    ZStack {
      Color.backgroundDark.ignoresSafeArea()

      if isWorkoutActive {
        // トレーニング中のライブ画面
        WorkoutView(viewModel: viewModel) {
          Task {
            await viewModel.finish()
            isWorkoutActive = false
          }
        }
        .transition(.opacity)
      } else if let summary = viewModel.summary {
        // 終了後のサマリー画面
        SummaryView(summary: summary) {
          viewModel.summary = nil
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      } else {
        // ホーム画面
        homeContent
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: isWorkoutActive)
    .preferredColorScheme(.dark)
  }

  /// ホーム画面（開始ボタンと簡単な説明のみのミニマルな構成）
  private var homeContent: some View {
    VStack(spacing: 24) {
      Spacer()

      // アプリロゴ
      VStack(spacing: 8) {
        Image(systemName: "figure.strengthtraining.functional")
          .font(.system(size: 64))
          .foregroundStyle(.neonGreen)
        Text("TrueRep")
          .font(.system(size: 44, weight: .black, design: .rounded))
          .foregroundStyle(.white)
        Text("リアルタイム動作解析")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.5))
      }

      Spacer()

      // 使い方の要点（最小限）
      VStack(alignment: .leading, spacing: 12) {
        instructionRow(icon: "iphone", text: "スマホを立てかけて全身を映す")
        instructionRow(icon: "person.fill.viewfinder", text: "正面・側面どこからでもOK")
        instructionRow(icon: "figure.squat", text: "スクワットを開始すると自動計測")
      }
      .padding(20)
      .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

      // 開始ボタン
      Button {
        isWorkoutActive = true
        Task { await viewModel.start() }
      } label: {
        Text("スタート")
          .font(.title3.bold())
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 18)
          .background(Color.neonGreen, in: RoundedRectangle(cornerRadius: 16))
      }
    }
    .padding(24)
  }

  /// 使い方の1行表示
  private func instructionRow(icon: String, text: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.neonGreen)
        .frame(width: 28)
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.85))
    }
  }
}

#Preview {
  ContentView()
}
