# kaizen.md — 例文生成の精度改善計画

作成日: 2026-07-02
対象問題: 写真に食べ物や花瓶が写っていても、「テーブルを拭いてパソコンで作業しています」のような
テーブル・PC中心の文になり、載っている物が無視される。

## 現行仕様との関係（2026-09-06整理）

本文は作成日時点の分析・改善提案を含む記録であり、全項目が現在の実装や必須条件を表すものではない。
最新の明示的なユーザー要件とREADMEの現行仕様を優先し、再開する項目の実装状態はコードとテストで確認する。
この整理はアプリの仕様追加・モデル差し替え・APIキー変更を指示するものではない。

| 箇所 | 現在の扱い |
| --- | --- |
| §1・§5-2の送信項目 | READMEの `OpenAI Scene Payload` が正本。`location_label` は送らず、生成画面の `situation` を使う |
| §5-3・§5-4の行動禁止と修復例 | 過去の提案。整理・掃除などの動詞を一律に禁止せず、写真根拠とソフトな多様性ヒントで偏りを抑える |
| §7のメモ入力強化 | 廃止。生成画面にはメモの代わりに場所のプルダウンを置く |
| キーワード編集・関係情報 | READMEの現行仕様を参照する。ここにある数値やコード例だけで実装済みと判断しない |
| モデル更新・追加UX・評価目標 | 提案・当時の目安として保持。対象作業の承認範囲と現在の実装を確認し、無関係な変更を併せて実行しない |

---

## 1. 現状の仕組み（コード調査結果）

```
写真 (UIImage)
  └─ ImageKeywordService.detectKeywords()          … 端末内解析
       ├─ YOLOv3TinyInt8LUT 物体検出 (COCO 80クラス, conf≥0.25)
       ├─ saliency領域切り抜き → 分類 (conf≥0.05 / 0.08)
       ├─ MobileNetV2Int8LUT 分類 (ImageNet-1k, conf≥0.05)
       └─ VNClassifyImageRequest 分類 (Apple約1,300クラス, conf≥0.08)
       → 最大16個のフラットな {label, confidence, count} に統合
  └─ SceneContextFactory.makeContext()             … 時刻/曜日/メモを付加（位置ラベルはAPIへ送らない）
  └─ OpenAILessonPromptBuilder.buildPrompt()       … 指示文 + scene JSON
  └─ OpenAILessonService.generateLesson()          … Responses API (テキストのみ)
       └─ 形式・内容バリデーション失敗時のみ repair 再生成 (最大4回)
```

現行仕様として維持する制約:

- **写真はOpenAIへ送らない**（写真送信機能・ON/OFF設定も作らない）
- 送信項目はREADMEの `OpenAI Scene Payload` に従う（旧メモUIは復活させない）
- 固定カテゴリーや勝手なタグで写真内容を決めつけない

→ 本計画は**この仕様内での改善を主軸**とし、仕様改訂が必要な案は §6 に分離した。

---

## 2. 根本原因の分析

「抽出が拙い」と「LLMが無視する」の複合。重要度順に6つ。

### 原因A: 前景/背景の区別がなく、背景（家具）が主役になる【主因】

- `dining table` `laptop` `chair` はYOLOが得意な大きい物体で confidence が高く、
  `sortedKeywords()` の confidence 降順ソートで**常に先頭**に来る。
- テーブルに載った食べ物・花瓶は小さく confidence が低い → 後方に沈むか脱落。
- プロンプトの要求は「**at least one** concrete object or action」なので、LLMは
  先頭の安全なキーワード（table/laptop）1つで条件を満たし、残りを捨てる。
- さらに「Do not invent objects」が強いため、confidence の低い食べ物には触れない
  方が安全、という方向にLLMが倒れる。→ ユーザーが見た症状そのもの。

### 原因B: 物体間の関係（何が何の上にあるか）が捨てられている

- `normalizeObjectObservations()` がYOLOの boundingBox を破棄し、ラベルと件数だけ残す。
- 「banana と dining table が写っている」ことは伝わるが「banana が table の**上に載っている**」
  ことは伝わらない。LLMには両者を結びつける根拠がない。

### 原因C: saliency切り抜きの座標系バグ（回転写真でクロップ位置がズレる）

- `detectSaliencyClassificationKeywords()` は Vision リクエストに `input.orientation` を
  渡すため、返る `boundingBox` は**回転適用後（正立）座標系**。
- しかし `cropImage(input.cgImage, ...)` は**未回転の生 cgImage** に対して切り抜く。
- カメラ縦撮り写真は通常 orientation = `.right` なので、クロップが実際の被写体と
  ズレた領域になり、無意味な分類結果（ノイズキーワード）を量産する。
- 前景の小物を拾う役割はこの saliency 経路が担っているため、このバグは
  「載っている物が拾えない」症状に直結する。

### 原因D: 認識モデルが古く、語彙が狭い

- YOLOv3-Tiny (2018年, Int8量子化): COCO 80クラスのみ。食品は
  banana / apple / sandwich / orange / broccoli / carrot / hot dog / pizza / donut / cake の
  **10種だけ**。ご飯・パン・麺・和食はすべて認識不能。Tiny版はフル版より大幅に低精度で
  小物体に弱い。
- MobileNetV2 (ImageNet-1k): 犬種120種などクラス粒度が偏っており、日常物体の
  誤ラベル（例: 湯呑み→"cup"以外の珍クラス）が混ざる。

### 原因E: 閾値が低すぎてノイズが信号を希釈する

- 分類系の閾値 0.05 / 0.08 は実質ノーフィルタ。最大16個の枠が
  低確信ラベルで埋まり、LLMから見ると玉石混交。
- クロップ最小サイズ 16px も小さすぎ、豆粒画像の分類結果（ゴミ）が混入する。

### 原因F: 「前景を無視した文」を検知する仕組みがない

- `GeneratedLessonPayload.isValid()` の検証は言語・形式のみ
  （インドネシア語らしさ、日本語訳、語彙数、行数）。
- 「主文が背景キーワードしか使っていない」ことはアプリ側で検知できず、
  当時の repair ループ（最大2回）が本件では一度も発火しなかった。

---

## 3. 改善の全体方針

| フェーズ | 内容 | 種別 | 期待効果 | 目安工数 |
|---|---|---|---|---|
| P0 | バグ修正・閾値調整 | 仕様内・小変更 | ノイズ激減、前景検出の回復 | 0.5〜1日 |
| P1 | 前景/背景ロール + 関係情報 + 接地検証 | 仕様内・本命 | 「載っている物」が主文に入る | 2〜3日 |
| P2 | 認識モデルの近代化 | 仕様内 | 語彙拡大・小物体精度向上 | 2〜5日 |
| P3 | UX: キーワード編集チップ | 仕様内 | 体感精度の底上げ | 1〜2日 |
| P4 | 端末内VLMキャプション | **要仕様改訂** | 質的ブレークスルー | 調査込み1週間〜 |

P0+P1 だけで報告された症状（食べ物・花瓶の無視）は大きく改善する見込み。

---

## 4. Phase 0 — 即効修正（ImageKeywordService.swift）

### 4-1. saliency クロップの座標系バグ修正

方針: 入力画像を**最初に一度だけ正立化（orientation = .up に再描画）**し、
以後すべてのリクエストとクロップを同一座標系で扱う。個別に boundingBox を
逆変換するより単純で、今後同種のバグを構造的に防げる。

```swift
// VisionImageInput.init(image:) を変更
init(image: UIImage) throws {
    // 正立化 + 長辺1536px程度への縮小を同時に行う（全Visionリクエストが高速化）
    let normalized = image.normalizedUp(maxDimension: 1536)
    guard let cgImage = normalized.cgImage else {
        throw ImageAnalysisError.invalidImage
    }
    self.cgImage = cgImage
    self.orientation = .up
}
```

`normalizedUp(maxDimension:)` は `UIGraphicsImageRenderer` で1回再描画するだけ。
12MP写真でも数十ms程度で、YOLO入力(416px)には無損失。

### 4-2. 閾値・上限の調整

```swift
private static let minimumObjectConfidence: VNConfidence = 0.25        // 据え置き
private static let minimumModelClassificationConfidence: VNConfidence = 0.15  // 0.05 → 0.15
private static let minimumClassificationConfidence: VNConfidence = 0.20       // 0.08 → 0.20
private static let maximumKeywords = 10                                // 16 → 10
```

- `VNClassifyImageRequest` は生confidenceではなく、公式推奨の
  `observation.hasMinimumPrecision(0.5, forRecall: 0.5)` でのフィルタに置き換えるとさらに良い。
- `cropImage` の最小サイズを 16px → **画像長辺の5%かつ64px以上** に引き上げ。

### 4-3. ノイズラベルの丸め（決めつけない範囲で）

ImageNet系の過剰に細かいクラスを日常語へ丸める軽量マッピングを導入する。
「固定カテゴリーで決めつけない」仕様には反しない（上位語への正規化であり、
写っていない物を足すわけではないため）。

```swift
// 例: 犬種→dog、椅子亜種→chair、"web site"等の非物体クラス→除外
private static let labelNormalization: [String: String?] = [
    "golden retriever": "dog",
    "tabby": "cat",
    "web site": nil,       // 除外
    "envelope": nil,
    // …初期は30〜50件で十分。ゴールデンセット(§8)で育てる
]
```

---

## 5. Phase 1 — 構造化シーン情報と接地検証【本命】

### 5-1. boundingBox を保持し、前景/背景ロールと関係を算出

`ImageKeyword` を拡張（`count` と同様に decodeIfPresent でデフォルトを与えれば
既存の保存データ・`StoredJSONCodingTests` と後方互換）:

```swift
// Sources/DailyLangCore/SceneContext.swift
public enum KeywordRole: String, Codable, Sendable {
    case foreground   // 主役候補: 食べ物、花瓶、道具など
    case surface      // 面・家具: dining table, desk, counter, bed…
    case context      // 環境: room, indoor, wall…（分類系由来）
}

public struct ImageKeyword: Codable, ... {
    public var label: String
    public var confidence: Double
    public var count: Int
    public var role: KeywordRole   // decodeIfPresent ?? .foreground
}
```

ロール判定は少数の**面・家具ラベル集合**（COCOの dining table / desk(分類系) / chair /
couch / bed / bench + Vision分類のシーン系ラベル）だけを surface/context に落とし、
**それ以外はすべて foreground** とする。「写真内容を決めつけない」原則と両立する
最小限の分類。

関係はYOLOの boundingBox から幾何ヒューリスティクスで算出:

```swift
// ImageKeywordService 内。Vision座標は左下原点・正規化済み
private static func isOn(_ item: CGRect, _ surface: CGRect) -> Bool {
    let horizontalOverlap = item.midX >= surface.minX && item.midX <= surface.maxX
    let restsOnUpperHalf = item.minY >= surface.midY - 0.05
        && item.minY <= surface.maxY + 0.10
    return horizontalOverlap && restsOnUpperHalf
}
// → relations: ["banana on dining table", "vase on dining table", ...]
```

厳密なシーングラフは不要。「on」1種類（+必要なら "held by person"）で十分効く。

### 5-2. ペイロード拡張（OpenAILessonPromptBuilder.swift）

`OpenAIScenePayload` に `relations: [String]` を追加し、`image_keywords` は
**foreground → surface → context の順**で並べ替えて出力する（LLMは先頭を重視する）。

関係情報を示す部分JSONの例（現行の全送信項目はREADMEを参照）:

```json
{
  "image_keywords": [
    {"label": "banana", "confidence": 0.27, "count": 2, "role": "foreground"},
    {"label": "vase",   "confidence": 0.31, "count": 1, "role": "foreground"},
    {"label": "laptop", "confidence": 0.88, "count": 1, "role": "foreground"},
    {"label": "dining table", "confidence": 0.92, "count": 1, "role": "surface"}
  ],
  "relations": ["banana on dining table", "vase on dining table"],
  "situation": "at home", "time": "08:15", "day": "Thursday",
  "user_note": "", "language_level": "beginner"
}
```

### 5-3. プロンプト改訂（instructions への追加・置換）

以下は当時の置き換え案であり、そのまま適用しない。現在は前景の根拠を活かしつつ、
特定の生活動詞を一律に禁止しない。個数を増やすために写っていない物や行動を追加しない。

```text
- Keywords with role "surface" or "context" (table, desk, room) are background.
  They must NOT be the topic of the main sentence. Use them only as location
  phrases such as "di atas meja" or "di kamar".
- When "foreground" keywords exist, the main sentence must mention at least
  TWO foreground objects, or ONE foreground object together with its relation
  from `relations`.
- Prefer distinctive foreground objects (food, flowers, tools) over generic
  ones (laptop, phone) when both are present.
- Wiping, cleaning, or working at furniture is invalid as the main topic
  unless the user note says so.
```

### 5-4. 接地（grounding）検証で repair ループを発火させる

この節のコードは当時の提案例。現在のエラーコード・修復条件は実装とREADMEで確認する。
整理・掃除などの語があることだけで修復対象にしてはいけない。

構造化出力スキーマ（OpenAILessonService.swift の `ResponsesTextConfig.lessonJSON`）に
`used_keywords: [string]`（モデルが主文で使った image_keywords のラベルをエコーする
フィールド）を追加し、アプリ側で検証する:

```swift
// OpenAILessonService.generateLesson() 内
let foregroundLabels = Set(context.imageKeywords
    .filter { $0.role == .foreground }.map { $0.label.lowercased() })

let usedForeground = payload.usedKeywords
    .contains { foregroundLabels.contains($0.lowercased()) }

if !foregroundLabels.isEmpty && !usedForeground {
    // repair ループ（maxRepairAttempts=4）に専用メッセージで再生成させる
    repairMessage = """
    The previous main sentence ignored all foreground objects and focused on
    background furniture. Regenerate: the main sentence must be about the
    foreground objects (e.g. the food or flowers on the table), not the table.
    """
    continue
}
```

狙いは画像根拠を無視した出力の検出であり、「テーブルを拭く」などの語句そのものの排除ではない。
修復を追加する場合は有効な例文を拒否しないことと、再試行によるAPIコストを検証する。

### 5-5. 付随作業

- AGENTS.md のルールに従い、ペイロード仕様変更を README（または仕様MD）へ同時反映。
- `OpenAILessonPromptTests` に「surface ロールのみのとき」「relations があるとき」の
  プロンプト/ペイロードのスナップショットテストを追加。

---

## 6. Phase 2 — 認識モデルの近代化（すべて端末内・仕様内）

優先度順に2案。併用も可。

### 案1: 物体検出器を YOLOv3-Tiny → YOLO11s/YOLOv8s (Core ML) に差し替え

- 同じCOCO 80クラスでも mAP が大幅に向上し、**小物体（テーブル上の食器・果物）の
  検出率が上がる**。Ultralytics から Core ML へ直接エクスポート可能
  （`model.export(format="coreml", nms=True)`）。
- `bundledVisionModel(named:)` の差し替えとモデル同梱だけで済み、
  パイプライン変更は不要。サイズは s モデルで20MB前後。
- 限界: クラス語彙は80のまま（和食・文具などは次の案で補う）。

### 案2: MobileCLIP によるゼロショット分類で語彙を自前定義

- Apple がOSS公開している MobileCLIP（Core ML対応・ANEで高速）で、
  画像埋め込みと**自作の日常語彙リスト**（200〜500語: rice, noodles, bento,
  chopsticks, mug, notebook, pen, flower vase, …日本の生活語彙を含む）の
  テキスト埋め込みの類似度でキーワード化する。
- ImageNetの奇妙なクラス粒度から解放され、**アプリの目的（日常会話の題材）に
  最適化した語彙**で抽出できるのが最大の利点。
- テキスト埋め込みはビルド時に事前計算して同梱すれば、実行時は画像埋め込み
  1回 + 内積のみで軽い。
- 注意: 語彙リストが「固定カテゴリーで決めつけない」に抵触しないよう、
  saliency クロップ単位で適用し、閾値未満は出さない設計にする。

---

## 7. Phase 3 — UX改善（抽出が外れたときの逃げ道を作る）

認識は確率的に必ず外れる。外れたときにユーザーが1タップで直せる導線が
体感精度を最も上げる。

- **キーワードチップ編集**: 生成開始前（または GeneratingView の前段）に検出
  キーワードをチップ表示し、タップで除外・自由入力で追加できるようにする。
  追加されたキーワードは confidence=1.0 / role=foreground として送る。
  🎯 空状態（何も検出できなかったとき）は「写っている物を1つ入力してください」を表示。
- **旧案・廃止: userNote の導線強化**: メモ入力を促す案は採用しない。
  現在は撮影後の場所プルダウンとキーワード編集を使う。`user_note` は互換フィールドとして残る。
- **生成後フィードバック**: レッスン画面に「写真に合っていた / いなかった」の
  2択を置き、`DiagnosticsExportService` 経由でローカル集計 → §8 の指標の実測に使う。
- 🎯 いずれも JP/EN 両対応・VoiceOverラベル必須（既存方針に合わせる）。

---

## 8. 検証方法（やったことの証明）

### 8-1. ゴールデンセットでキーワード抽出を定量評価

- 代表シーン20〜30枚（机+食べ物、机+花瓶、料理単体、カフェ、屋外、散らかった机…）に
  期待する foreground ラベルを人手付与した `tests/golden/expected.json` を作る。
- 既存の `scripts/run-image-keyword-check.swift` を拡張し、
  **foreground recall / ノイズ率（期待外ラベル比率）** を出力、変更前後で比較する。

```
指標と目標値（初期目安）
- foreground recall@10 : 0.45（現状想定）→ 0.80
- ノイズ率             : 0.50 → 0.20 以下
- 主文の接地率(※)      : 0.90 以上
※ used_keywords に foreground が1つ以上含まれるレッスンの割合
```

### 8-2. レッスンレベルの回帰チェック

- ゴールデンセットの SceneContext を固定入力にして生成を数回走らせ、
  「主文が surface ラベルのみを主題にしていないか」を `used_keywords` で機械判定。
- `OpenAILessonPromptTests` / `StoredJSONCodingTests` を新ペイロードに追随させる。

### 8-3. 完了条件

- 「テーブル+食べ物」「テーブル+花瓶」の実写真で、主文が載っている物を
  主題にすることを実機で確認（AGENTS.md: ビルド成功だけで完了と言わない）。

---

## 9. 実施順序（推奨）

1. **P0**(§4): 正立化バグ修正 → 閾値調整 → ノイズ丸め。ここだけで前景検出が目に見えて回復するはず。
2. **§8-1 のゴールデンセット整備**: 以降の変更を全部この物差しで測る。
3. **P1**(§5): ロール + relations + プロンプト改訂 + used_keywords 接地検証。**症状の直接解**。
4. **P3**(§7): キーワードチップ（P1のペイロードがあれば実装は薄い）。
5. **P2**(§6): 数値がまだ足りなければモデル差し替え（案1→案2の順）。
6. **P4**: それでも質が頭打ちなら、端末内VLM（下記）の仕様改訂を検討。

---

## 10. 【要仕様改訂】将来オプション: 端末内VLMキャプション

- FastVLM など端末内で動く小型VLMで「A laptop, a plate of bread, and a vase of
  flowers on a wooden table」のような**1〜2文のシーン記述を端末内生成**し、
  キーワードの代わり/補完として送る案。
- **写真は引き続き外部送信しない**ためプライバシー実質は保たれるが、AGENTS.md の
  「キーワード、時刻、曜日、位置ラベル、メモ**だけ**を送る」の文言改訂と README の
  プライバシー記述更新が前提。モデルサイズ（数百MB級）・レイテンシ・発熱が
  トレードオフ。
- なお「写真そのものをOpenAIへ送る」案は AGENTS.md で明示的に禁止されているため、
  本計画では選択肢に含めない。

---

## 付録: 今回の変更対象ファイル一覧

| ファイル | 変更内容 |
|---|---|
| `DailyLangApp/Services/ImageOrientation+Vision.swift` | 正立化+縮小 (P0) |
| `DailyLangApp/Services/ImageKeywordService.swift` | 閾値/丸め (P0)、bbox保持・ロール・relations (P1) |
| `Sources/DailyLangCore/SceneContext.swift` | ImageKeyword.role 追加 (P1) |
| `Sources/DailyLangCore/OpenAILessonPromptBuilder.swift` | ペイロード拡張・指示文改訂 (P1) |
| `DailyLangApp/Services/OpenAILessonService.swift` | used_keywords スキーマ + 接地検証 repair (P1) |
| `DailyLangApp/Views/CameraView.swift` ほか | キーワードチップUI (P3) |
| `scripts/run-image-keyword-check.swift` | recall/ノイズ率の計測 (§8) |
| `Tests/DailyLangCoreTests/*` | 新ペイロードの回帰テスト (§8) |
| `README.md` | ペイロード仕様・検証手順の更新（AGENTS.md ルール） |
