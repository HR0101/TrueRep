//
//  TempoAnalyzer.swift
//  TrueRep
//
//  レップ時間の履歴から動作テンポ（BPM）を算出する
//

import Foundation

/// 動作テンポ（BPM）の算出
nonisolated struct TempoAnalyzer: Sendable {

  /// BPM算出に使う直近レップ数
  private static let windowSize = 4
  /// 直近のレップ時間（秒）
  private var recentDurations: [TimeInterval] = []

  /// 現在のBPM（1分あたりのレップ数）．レップが1回もなければnil
  var bpm: Double? {
    guard !recentDurations.isEmpty else { return nil }
    let average = recentDurations.reduce(0, +) / Double(recentDurations.count)
    guard average > 0 else { return nil }
    return 60.0 / average
  }

  /// 完了したレップの所要時間を追加する
  mutating func add(duration: TimeInterval) {
    guard duration > 0 else { return }
    recentDurations.append(duration)
    if recentDurations.count > Self.windowSize {
      recentDurations.removeFirst(recentDurations.count - Self.windowSize)
    }
  }

  /// 履歴をリセットする
  mutating func reset() {
    recentDurations.removeAll()
  }
}
