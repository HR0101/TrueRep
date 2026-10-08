//
//  CameraPreviewView.swift
//  TrueRep
//
//  AVCaptureSessionの映像をSwiftUIに表示するプレビュー
//

import SwiftUI
import UIKit
import AVFoundation

/// カメラプレビュー（AVCaptureVideoPreviewLayerのラッパー）
struct CameraPreviewView: UIViewRepresentable {

  /// 表示するキャプチャセッション
  let session: AVCaptureSession

  /// プレビューレイヤーを持つUIView
  final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
      AVCaptureVideoPreviewLayer.self
    }

    /// プレビューレイヤー
    var previewLayer: AVCaptureVideoPreviewLayer {
      layer as! AVCaptureVideoPreviewLayer
    }
  }

  func makeUIView(context: Context) -> PreviewUIView {
    let view = PreviewUIView()
    view.previewLayer.session = session
    // 画面いっぱいに表示する（骨格オーバーレイも同じ変換で重ねる）
    view.previewLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: PreviewUIView, context: Context) {
    // セッションは固定のため更新処理は不要
  }
}
