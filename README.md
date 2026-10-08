# TrueRep (iOS)

Apple Vision フレームワークを活用し、完全オンデバイスで動作する筋トレ特化型リアルタイム・レップカウンター＆フォーム分析 iOS アプリです。

---

## ✨ 主な機能

- **オンデバイス骨格推定 (Vision Framework)**
  - `VNDetectHumanBodyPoseRequest` を用いた高速・プライバシー配慮の関節点トラッキング
  - カメラ映像上へのリアルタイム骨格オーバーレイ描画 (`SkeletonOverlayView`)
  - 正面・側面などの向きを自動検出 (`OrientationDetector`)
- **高精度レップカウント (RepCounter)**
  - 関節角度の遷移をステートマシンで監視し、反復回数を正確にカウント
- **フォーム解析 & テンポ計測 (FormAnalyzer & TempoAnalyzer)**
  - 各レップの可動域（ROM）やフォームの崩れをリアルタイム検出
  - 収縮（Concentric）・伸張（Eccentric）動作のテンポ測定
- **ワークアウトダッシュボード**
  - セッション中の HUD 表示（レップ数、フォーム状態、テンポ）
  - セッション終了後の総合サマリー表示 (`SummaryView`)

---

## 🛠 技術構成

- **プラットフォーム**: iOS 16.0+
- **言語**: Swift
- **UIフレームワーク**: SwiftUI
- **画像・推論フレームワーク**:
  - `Vision` (骨格推定)
  - `AVFoundation` (カメラプレビュー & フレームキャプチャ)
- **アーキテクチャ**: MVVM (`WorkoutViewModel`)

---

## 📂 プロジェクト構成

```
TrueRep/
├── TrueRep/
│   ├── TrueRepApp.swift
│   ├── Camera/                  # カメラ制御 & 姿勢推定
│   │   ├── CameraManager.swift
│   │   └── PoseEstimator.swift
│   ├── Analysis/                # 幾何計算 & レップ判定エンジン
│   │   ├── AngleCalculator.swift
│   │   ├── FormAnalyzer.swift
│   │   ├── OrientationDetector.swift
│   │   ├── RepCounter.swift
│   │   └── TempoAnalyzer.swift
│   ├── Models/                  # データモデル
│   │   ├── BodyPose.swift
│   │   └── WorkoutTypes.swift
│   ├── ViewModels/
│   │   └── WorkoutViewModel.swift
│   └── Views/                   # UI
│       ├── CameraPreviewView.swift
│       ├── SkeletonOverlayView.swift
│       ├── WorkoutView.swift
│       └── SummaryView.swift
└── TrueRep.xcodeproj
```

---

## 🚀 使い方

1. Xcode で `TrueRep.xcodeproj` を開きます。
2. 実機を選択してビルド＆実行します。
3. カメラを全身または運動部位が映る位置に固定し、ワークアウトを開始します。
