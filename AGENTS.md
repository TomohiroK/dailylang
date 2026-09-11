# AGENTS.md

このファイルは DailyLang プロジェクトで Codex/エージェントが作業するときの必須ルールです。
上位指示に従ったうえで、最新の明示的なユーザー要件、承認済みの現行仕様、過去の提案の順に扱います。文書が古い場合はユーザー要件を上書きせず、実装と同じ作業で該当文書を更新してください。

## 最優先ルール

- 日本語で応答する。
- メモリは調査先や過去の判断を探す補助に使い、現在の実装・署名・実機状態は現物で確認する。
- 作業前に `README.md` と変更対象に関連する仕様MDを読み、最新のユーザー要件との差分を確認する。
- 機能を追加・変更したら、同じ作業単位で必ずREADMEまたは仕様MDを更新する。
- テストはMDファイルの仕様・検証項目から導く。コードを見て通りそうなテストだけを選ばない。

## このプロジェクトの正しい仕様ソース

- `README.md`: 現在のMVP範囲、プライバシー方針、検証手順、実機確認項目。
- 追加の仕様MD: 対象範囲と承認・更新状況を確認する。存在するだけでREADMEやユーザー要件より優先しない。
- `kaizen.md`: 改善計画と当時の分析。冒頭の現行仕様との差分を読み、過去の提案を現行の必須条件として復活させない。
- ソースコード: 実装状態の確認には使うが、仕様の代替にしない。

## DailyLangの重要仕様

- 写真はOpenAIへ送らない。今後も写真送信機能や写真送信ON/OFF設定を作らない。
- OpenAIは毎回のレッスン生成で使う。OpenAI有効/無効スイッチを作らない。
- APIキーは開発環境からKeychainへ渡される。ユーザーがアプリ内で毎回入力しないと動かない状態はバグ。
- APIに送る構造化フィールドの正本はREADMEの `OpenAI Scene Payload`。写真・GPS座標・自動推定した現在地ラベルは送らない。学習レベル・文法パターン・反復表現の多様性ヒントも同節の範囲で扱う。
- 作成言語はインドネシア語と英語から選べる。既定値と既存レッスンの互換値はインドネシア語にする。
- 場所は撮影後の生成画面で「ランダム」を既定値として選ぶ。候補は自宅、友人宅、会社、学校、病院・動物病院、スーパー・コンビニ、デパート・モール、駅・空港、車内・機内、公園、お店、レストラン・カフェ、自然の中。設定画面に場所の恒久設定を置かない。ランダムは生成ごとに具体候補を1つ選び、現在地の推定には使わない。
- 場所は背景文脈であり、行動を決めつける指示ではない。自宅・友人宅では、現在の画像根拠とユーザー入力を優先し、食事・飲み物、持ち物や道具の使用、読む・見る・聞く、休憩・会話、ペットや植物、移動、物の受け渡し・配置、整理や掃除を含む幅広い生活語彙から選ぶ。整理・整える系を固定の禁止語にはしない。直近6件の自宅・友人宅かつ同一作成言語の保存済み本文で同じ生活表現が2回以上出たときだけ、今回の生成に「別の根拠ある表現を優先する」というソフトな多様性ヒントを渡す。写真根拠に最も自然なら同じ表現も使えるため、別の偏りや固定カテゴリーを作らない。
- OCRだけで物体写真を理解しようとしない。物体認識は端末内の画像解析を使う。
- 固定カテゴリーや勝手なタグで写真内容を決めつけない。
- 前景キーワードごとの行動候補は、単一の定番動詞に固定せず複数用意する。食べ物、飲み物・容器、本・書類、機器、持ち物、ペット、植物、交通、人、生活用品などでは、使用・観察・運搬・準備・受け渡し・配置などから写真根拠に合うものを選ぶ。これは生成言語の候補であり、画像内容を固定カテゴリーで決めたり、写っていない行動を事実として追加する根拠にはしない。
- 撮影後は画像キーワードを確認・削除・追加できるようにし、ユーザーが直したキーワードをOpenAIへ送る。
- DUO式メイン例文は選択した作成言語の1文。初級は7単語以下、中級は10〜15単語、上級は20〜40単語を目安にするが、単語数だけを理由に有効な例文をエラー・再生成・破棄しない。
- 例文の文法・時制・接続表現は生成ごとに巡回させる。進行形だけに偏らせず、過去完了、予定、目的、順序、原因、追加、選択、対比、仮定を写真に合う範囲で使い分ける。`sambil` と `sepertinya` は専用の巡回パターン以外で埋め草として使わない。
- 生成中に実際は行っていない処理名を表示しない。
- OpenAI応答、本文、学習用の単語・日本語訳、保存結果が欠けた場合は成功扱いにしない。既存のエラーコードと秘密情報を含まない診断で失敗段階を区別する。

## Home画面の必須仕様

- Homeには今日の通知回数、今日のレッスン数、今すぐ撮るボタンを表示する。
- Homeの最新レッスンカードには、選択した作成言語の例文と日本語訳を直接表示する。
- 生成後にHomeへ戻った時点で、最新レッスンの本文が見えていなければバグ。
- 詳細画面へ遷移できるだけではHome仕様を満たしたことにならない。

## Review画面と保存の必須仕様

- 生成したレッスンはSwiftDataに保存される。
- 保存済みレッスンはHomeの最新レッスンとReviewから確認できる。
- Reviewは「過去の例文を復習する」画面であり、保存済み例文が消えたように見える状態はバグとして扱う。
- 「覚えた」「もう一度」の状態変更は保存データを失わせてはいけない。
- Reviewに出ない問題を調べるときは、保存失敗、クエリ条件、ステータス絞り込み、画面更新の順に切り分ける。
- Reviewの単語フラッシュ確認は、保存済みかつ学習者向けとして有効なレッスンの本文内単語だけを集計元にする。画像キーワードや本文にない単語を出してはいけない。同じ単語は同一レッスン内で1回だけ数え、言語別の出現頻度を端末内の学習メモリに保存する。
- Reviewの単語出題順は、新規登録語を最優先にし、その後はFSRS（Free Spaced Repetition Scheduler）のローカルなDifficulty・Stability・Retrievability状態と次回復習日時に従う。同順位では出現頻度の高い語を先に出す。単語の4段階評価と頻度メモリは、例文の保存データを消したりReviewから隠したりしてはいけない。

## 検証ルール

READMEの `Verification` と `Before calling the MVP complete on a real iPhone` をテスト基準にする。
以下は検証候補であり、毎回すべてを実行する義務ではない。変更した仕様と影響経路に応じて選び、十分な証拠が揃ったら終了する。失敗・追加変更・未解決の懸念がある場合に範囲を広げる。

- 文書・スキルのみ: 差分、参照リンク、指示の整合性を確認する。アプリビルド、実API呼び出し、実機インストールは不要。
- 署名更新のみ: READMEの更新手順に沿って署名・プロファイル期限、対象実機へのインストールと起動を確認する。APIキーやアプリ仕様は変更しない。
- アプリ変更: MDの該当要件と報告された再現条件を基準に、ロジック・保存・UI・実機固有機能の影響箇所を検証する。

```bash
swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO build -quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build/XcodeDerivedDataDevice -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO build -quiet
```

生成・保存の診断が必要な変更では、承認された実機とAPI利用範囲で次を利用できる。署名更新のためだけにこの診断を実行しない。

```bash
ALLOW_DEVICE_REGISTRATION=1 scripts/run-ios-device.sh <device-udid> -DailyLangExportDiagnostics
xcrun devicectl device copy from \
  --device <device-udid> \
  --domain-type appDataContainer \
  --domain-identifier com.tomohirok.dailylang \
  --source "Library/Application Support/Diagnostics/latest-device-diagnostics.json" \
  --destination /tmp/dailylang-device-diagnostics.json
cat /tmp/dailylang-device-diagnostics.json
```

ただし、診断JSONがreadyでも、HomeやReviewの画面表示まで確認したことにはならない。
画面仕様の不具合では、実機またはシミュレーターで該当画面の表示を確認する。

## 検証の報告基準

- MD上のどの仕様を検証したのかを言える。
- 実行したコマンドと結果を言える。
- Home、Review、LessonDetailなど画面仕様に関わる変更では、該当画面の表示確認を含める。
- OpenAI生成の実動作を確認済みとするには、今回の実リクエストに紐づく本文・日本語訳・本文内単語・保存状態の証拠が必要。モックや過去の診断JSONだけで実生成済みとは言わない。
- 未確認の項目がある場合は、成功扱いにせず「未確認」と書く。
- SwiftData保存の一時ストア診断だけで、実アプリのHome/Reviewに残ると判断しない。
- 単体テスト成功だけで、撮影から生成、保存、Home表示、Review表示の実フローが通ったと言わない。
- ユーザーが指摘した不具合を、別の正常系テストで上書きして説明しない。
- 通知の予約件数と、予定時刻の通知表示・通知タップ後の遷移は別の検証項目として報告する。
