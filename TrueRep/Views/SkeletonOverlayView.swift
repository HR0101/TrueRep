//
//  SkeletonOverlayView.swift
//  TrueRep
//
//  検出した骨格をカメラプレビューに重ねて描画するオーバーレイ
//

import SwiftUI

/// 骨格オーバーレイ
///
/// 推論は約15fpsだが，TimelineViewで毎フレーム再描画し，
/// 表示座標を目標座標へ指数補間することで60fpsの滑らかな描画を実現する．
/// フォームの状態（良好／警告）に応じて骨格の色が変わる
struct SkeletonOverlayView: View {

  /// 最新の姿勢検出結果
  let pose: BodyPose?
  /// フォームが良好か（色分け用）
  let isFormGood: Bool

  /// カメラバッファのアスペクト比（縦持ち720p: 幅720×高さ1280）
  private static let bufferAspect: CGFloat = 720.0 / 1280.0
  /// 補間の速さ（1秒あたりの追従率の指数係数）
  private static let smoothingRate: Double = 18.0

  /// 補間状態を保持する参照型ボックス
  ///
  /// TimelineViewが毎フレーム再描画するため，@Stateの書き換えによる
  /// ビュー無効化を発生させずに描画クロージャ内から直接更新する
  private final class InterpolationState {
    /// 表示用に補間された関節座標（ビュー座標系）
    var points: [JointName: CGPoint] = [:]
    /// 前回の描画時刻（補間のdt計算用）
    var lastDrawTime: TimeInterval?
  }

  /// 補間状態（ビューの再生成をまたいで保持する）
  @State private var interpolation = InterpolationState()

  var body: some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        let targets = targetPoints(in: size)
        let points = interpolate(
          toward: targets,
          at: timeline.date.timeIntervalSinceReferenceDate
        )
        draw(points: points, in: &context)
      }
    }
    .allowsHitTesting(false)
  }

  // MARK: - 座標変換

  /// 正規化座標（Vision系，原点左下）をアスペクトフィル済みのビュー座標へ変換する
  private func targetPoints(in size: CGSize) -> [JointName: CGPoint] {
    guard let pose, size.width > 0, size.height > 0 else { return [:] }

    // resizeAspectFillと同じ変換: バッファをビュー全体を覆うよう拡大し，中央寄せで切り抜く
    let viewAspect = size.width / size.height
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    if viewAspect > Self.bufferAspect {
      // ビューの方が横長: 幅に合わせて拡大し，上下がはみ出す
      scale = size.width / Self.bufferAspect
      offsetX = 0
      offsetY = (size.height - scale) / 2
    } else {
      // ビューの方が縦長: 高さに合わせて拡大し，左右がはみ出す
      scale = size.height
      offsetX = (size.width - scale * Self.bufferAspect) / 2
      offsetY = 0
    }

    var result: [JointName: CGPoint] = [:]
    for (name, joint) in pose.joints where joint.confidence >= BodyPose.minimumConfidence {
      // Visionは原点左下なのでYを反転する
      let x = joint.position.x * scale * Self.bufferAspect + offsetX
      let y = (1 - joint.position.y) * scale + offsetY
      result[name] = CGPoint(x: x, y: y)
    }
    return result
  }

  /// 表示座標を目標座標へ指数補間で近づける
  private func interpolate(
    toward targets: [JointName: CGPoint],
    at time: TimeInterval
  ) -> [JointName: CGPoint] {
    let dt = interpolation.lastDrawTime.map { max(0, time - $0) } ?? 0

    var updated: [JointName: CGPoint] = [:]
    // 経過時間に応じた追従率（フレームレートが変動しても挙動が一定になる）
    let factor = 1 - exp(-Self.smoothingRate * dt)
    for (name, target) in targets {
      if let current = interpolation.points[name] {
        updated[name] = CGPoint(
          x: current.x + (target.x - current.x) * factor,
          y: current.y + (target.y - current.y) * factor
        )
      } else {
        updated[name] = target
      }
    }

    // 次フレームの基準として保存する（参照型なのでビュー無効化は発生しない）
    interpolation.points = updated
    interpolation.lastDrawTime = time
    return updated
  }

  // MARK: - 描画

  /// 骨格（ボーンと関節）を描画する
  private func draw(points: [JointName: CGPoint], in context: inout GraphicsContext) {
    guard !points.isEmpty else { return }

    let boneColor: Color = isFormGood ? .neonGreen : .alertRed
    let jointColor: Color = isFormGood ? .white : .alertRed

    // ボーン（関節同士を結ぶ線）
    var bonePath = Path()
    for (from, to) in SkeletonConnection.bones {
      guard let fromPoint = points[from], let toPoint = points[to] else { continue }
      bonePath.move(to: fromPoint)
      bonePath.addLine(to: toPoint)
    }
    context.stroke(
      bonePath,
      with: .color(boneColor.opacity(0.9)),
      style: StrokeStyle(lineWidth: 4, lineCap: .round)
    )

    // 関節（点）
    for (_, point) in points {
      let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
      context.fill(Path(ellipseIn: rect), with: .color(jointColor))
    }
  }
}

// MARK: - アプリ共通カラー

extension Color {
  /// アクセント用のネオングリーン（フォーム良好）
  static let neonGreen = Color(red: 0.2, green: 1.0, blue: 0.5)
  /// 警告用のレッド（フォーム不良）
  static let alertRed = Color(red: 1.0, green: 0.23, blue: 0.27)
  /// 背景用のダークグレー
  static let backgroundDark = Color(red: 0.07, green: 0.07, blue: 0.09)
}

/// `.foregroundStyle(.neonGreen)`のような先頭ドット記法を使えるようにする
extension ShapeStyle where Self == Color {
  /// アクセント用のネオングリーン（フォーム良好）
  static var neonGreen: Color { Color.neonGreen }
  /// 警告用のレッド（フォーム不良）
  static var alertRed: Color { Color.alertRed }
  /// 背景用のダークグレー
  static var backgroundDark: Color { Color.backgroundDark }
}
