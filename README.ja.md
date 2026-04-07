# Coordify

> **[English version](README.md)**

macOS 向けの AltTab 風 Space スイッチャーです。**Option+Tab** を押すと、すべての Space のビジュアルオーバーレイが表示され、瞬時に切り替えられます。

Coordify はメニューバーエージェント（Dock アイコンなし）として動作し、Space 情報の取得に [yabai](https://github.com/koekeishiya/yabai) を使用します。

## 機能

- **Option+Tab オーバーレイ** — すべての Space のライブサムネイルを表示するダーク半透明の HUD パネル
- **2 つの操作モード** — トランジェントモード（Option を押しながら Tab でサイクル、離して確定）とピン固定モード（Option+Tab を一度タップしてパネルをロック、自由に操作）
- **フルスクリーンアプリ対応** — ネイティブフルスクリーンアプリが通常の Space と並んで表示され、それぞれに 1 文字のショートカットが割り当てられる
- **マルチディスプレイ対応** — 複数ディスプレイを自動検出して Space をディスプレイごとにグループ化。モニター切断後もレイアウトを記憶
- **リッチな Space カード** — 各カードにはデスクトップ壁紙上に合成されたウィンドウサムネイル、Space 名、ショートカットキーバッジ、実行中アプリ一覧を表示（選択時に展開）
- **キーボード・マウス・数字キー操作** — Tab、Shift+Tab、矢印キー、数字キー（1〜0）、フルスクリーンアプリ用の文字ショートカット、Enter、Escape、マウスクリックで操作

## 必要環境

- macOS 13.0 以降
- [yabai](https://github.com/koekeishiya/yabai)（SIP 無効のスクリプティングアディションは**不要**）
- [Taskfile](https://taskfile.dev/)（ビルド用）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [SwiftLint](https://github.com/realm/SwiftLint) & [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)（リント用）

## セットアップ

### 1. 権限の付与

初回起動時に 2 つの macOS 権限を求められます：

- **アクセシビリティ** — グローバルな Option+Tab ホットキーに必要です。この権限がないとキーボードイベントを検知できません。
- **画面収録** — ScreenCaptureKit による Space サムネイルのキャプチャに必要です。権限がなくても動作しますがサムネイルは空白になります。

### 2. Mission Control ショートカットの有効化

Coordify は macOS 組み込みの **Ctrl+数字** キーボードショートカットをシミュレートして Space を切り替えます。これらを macOS で有効にする必要があります：

1. **システム設定 > キーボード > キーボードショートカット > Mission Control** を開きます。
2. 使用する Space の数だけ **「デスクトップ 1 への切り替え」** から **「デスクトップ N への切り替え」** を有効にします。

起動時にショートカットが無効になっている場合、Coordify は手順を示すセットアップガイドパネルを表示します。

## ビルド & 実行

```bash
task build      # Xcode プロジェクト生成 + ビルド
task generate   # project.yml から Coordify.xcodeproj を再生成
task lint        # SwiftLint（strict）+ SwiftFormat --lint
task format      # SwiftFormat 自動修正
task clean       # ビルド成果物のクリーン
```

## 使い方

### スイッチャーを開く

**Option+Tab** を押すとオーバーレイが開きます。そこからの操作方法は 2 通りあります：

#### トランジェントモード（Option 長押し）

**Option** を押したまま **Tab** を繰り返しタップすると、Space を順番にサイクルします（**Shift** を加えると逆方向）。**Option** を離すと、ハイライトされている Space に切り替わります。macOS 標準の Cmd+Tab アプリスイッチャーと同様の、最も素早い切り替え方法です。

#### ピン固定モード（タップして離す）

**Option+Tab** を押してすぐに両方のキーを離すと、パネルが開いたまま固定（「ピン」）されます。自由に操作できます：

| 入力 | 動作 |
|---|---|
| **左 / 右矢印** | 選択を水平方向に移動 |
| **上 / 下矢印** | 選択を行間で移動 |
| **スクロール 上 / 下** | 上 / 下矢印キーと同じ |
| **Tab / Shift+Tab** | リスト内で前方 / 後方に移動；末端で隣接ディスプレイへラップ（マルチディスプレイ） |
| **数字キー（1〜0）** | そのショートカット番号の Space に直接ジャンプ |
| **文字キー** | そのショートカットに一致するフルスクリーンアプリにジャンプ |
| **Enter** | 現在の選択を確定して切り替え |
| **カードをクリック** | その Space を選択して切り替え |
| **Escape** | キャンセル — パネルを閉じて以前のアクティブアプリにフォーカスを戻す |
| **パネル外をクリック** | Escape と同じ |
| **Space バー** | 次のディスプレイの Space グループにサイクル（マルチディスプレイ） |
| **カードを右クリック** | マッピング内で Space を次のディスプレイに再割り当て |
| **Cmd+,** | ディスプレイマッピング JSON ファイルを手動編集用に開く |

### Space カードの表示内容

グリッド内の各カードには以下が表示されます：

- **サムネイル** — 壁紙上に合成された Space のウィンドウのスクリーンショット。フルスクリーンアプリの場合はウィンドウ画像がそのまま表示されます。
- **Space 名** — 通常の Space は「Desktop 1」「Desktop 2」など、フルスクリーンの Space はアプリ名。
- **ショートカットバッジ** — 通常の Space は数字（1〜0）、フルスクリーンアプリはアルファベット（A〜Z）、現在フォーカスされている Space は「ESC」。
- **アプリ一覧** — その Space で実行中のアプリのアイコンと名前（デフォルトで最大 3 つ、カード選択時にすべて表示）。Space が空の場合は「no apps」を表示。
- **視覚的インジケーター** — フォーカス中の Space は明るい背景、選択中のカードはアクセントカラーのボーダー、ホバー中のカードはわずかなハイライト。

### フルスクリーンアプリ

ネイティブフルスクリーンアプリ（例：Safari のフルスクリーン）は通常の Space と並んでリストに表示されます。Ctrl+数字ではなくアプリプロセスを直接アクティベートして切り替えます。各フルスクリーンアプリにはアプリ名に基づいて 1 文字のショートカットが自動的に割り当てられます。

### マルチディスプレイ対応

2 つ以上のディスプレイが接続されている場合、Coordify は Space をディスプレイごとにグループ化します。パネルのフッターには現在のディスプレイ名（例：「Built-in Retina Display」「DELL U2723QE」）が表示されます。ピン固定モードで **Space バー** を押すとディスプレイを切り替えられます。

**ディスプレイマッピングの永続化** — 複数ディスプレイ接続時に、Coordify は Space とディスプレイの対応を `~/Library/Application Support/Coordify/display-mapping.json` に保存します。ディスプレイを切断した後も、保存されたマッピングを使って Space を元のディスプレイごとに整理した状態を維持します。切断されたディスプレイの名前にはグレーアウトされた「(disconnected)」が付きます。

**自動バックアップ** — マッピングが保存されるたびに、`~/Library/Application Support/Coordify/backups/` にバックアップが書き込まれます。バックアップファイルは接続中のディスプレイ名とディスプレイ UUID の短いハッシュで名前が付けられます（例：`Built-in Retina Display_DELL U2723QE-a3f1c9b2.json`）。各ディスプレイ構成ごとにバックアップは 1 つだけ保持され、保存のたびに上書きされるため、各セットアップの最新マッピングが常に残ります。

Space カードを右クリックすると別のディスプレイにマッピングを変更でき、**Cmd+,** で JSON ファイルを直接開いて編集することもできます。

### メニューバー

Coordify は小さなグリッドアイコンでメニューバーに常駐します。メニューには以下が表示されます：

- 現在フォーカスされている Space の名前
- yabai が見つからない場合の警告
- ディスプレイマッピングファイルを開くリンク
- アクセシビリティ権限設定へのリンク
- 終了

## アーキテクチャ

```
Coordify/
├── Core/
│   ├── SpaceManager        — yabai に問い合わせ、Space ごとのアプリ情報を解決
│   ├── HotkeyInterceptor   — CGEventTap による Option+Tab 検知
│   ├── WorkspaceObserver    — Space 変更通知の監視
│   └── ThumbnailCache      — ScreenCaptureKit ベースのスクリーンショットキャプチャ
├── UI/
│   ├── SwitcherPanel        — オーバーレイ NSPanel（トランジェント + ピン固定モード）
│   ├── SpaceCardView        — サムネイルとアプリアイコン付きの Space カード
│   └── MenuBarController    — メニューバーのステータスアイテム
├── Adapters/
│   ├── YabaiClient          — 非同期 yabai CLI ラッパー
│   ├── DisplayMappingAdapter — マルチディスプレイの Space 割り当て永続化
│   └── ...
└── Models/
    ├── SpaceInfo
    ├── DisplayMapping
    └── ...
```

## ライセンス

[MIT License](LICENSE)
