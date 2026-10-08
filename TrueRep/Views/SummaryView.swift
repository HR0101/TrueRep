//
//  SummaryView.swift
//  TrueRep
//
//  トレーニング終了後の結果サマリー画面
//

import SwiftUI

/// セッション終了後のサマリー画面
struct SummaryView: View {

  /// 表示するサマリー
  let summary: WorkoutSummary
  /// 閉じるためのコールバック
  let onClose: () -> Void

  var body: some View {
    ZStack {
      Color.backgroundDark.ignoresSafeArea()

      VStack(spacing: 32) {
        Text("WORKOUT COMPLETE")
          .font(.headline.bold())
          .foregroundStyle(.neonGreen)
          .kerning(2)

        // 主要メトリクス
        HStack(spacing: 40) {
          metricItem(
            value: "\(summary.totalReps)",
            label: "総レップ",
            color: .neonGreen
          )
          metricItem(
            value: summary.averageBPM.map { String(format: "%.0f", $0) } ?? "–",
            label: "平均BPM",
            color: .white
          )
          metricItem(
            value: formattedDuration,
            label: "時間",
            color: .white
          )
        }

        // フォーム評価
        faultSection

        Spacer()

        Button(action: onClose) {
          Text("ホームへ戻る")
            .font(.headline.bold())
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.neonGreen, in: RoundedRectangle(cornerRadius: 16))
        }
      }
      .padding(24)
      .padding(.top, 32)
    }
    .preferredColorScheme(.dark)
  }

  /// セッション時間の表示用文字列（mm:ss）
  private var formattedDuration: String {
    let total = Int(max(0, summary.duration))
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  /// メトリクス1項目の表示
  private func metricItem(value: String, label: String, color: Color) -> some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.system(size: 44, weight: .black, design: .rounded))
        .foregroundStyle(color)
      Text(label)
        .font(.caption.bold())
        .foregroundStyle(.white.opacity(0.5))
    }
  }

  /// フォーム警告の振り返りセクション
  @ViewBuilder
  private var faultSection: some View {
    if summary.faultCounts.isEmpty {
      Label("フォームは良好でした", systemImage: "checkmark.seal.fill")
        .font(.headline)
        .foregroundStyle(.neonGreen)
        .padding(.vertical, 12)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        Text("フォームの注意点")
          .font(.subheadline.bold())
          .foregroundStyle(.white.opacity(0.7))
        ForEach(sortedFaults, id: \.fault) { item in
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.alertRed)
            Text(item.fault.message)
              .foregroundStyle(.white)
            Spacer()
            Text("\(item.count)回")
              .font(.headline.bold())
              .foregroundStyle(.alertRed)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 発生回数の多い順に並べた警告一覧
  private var sortedFaults: [(fault: FormFault, count: Int)] {
    summary.faultCounts
      .map { (fault: $0.key, count: $0.value) }
      .sorted { $0.count > $1.count }
  }
}
