# AGENTS.md

このファイルは DailyLang プロジェクトで Codex/エージェントが作業するときの必須ルールです。
会話履歴やエージェントの記憶より、このファイル、README、仕様MD、現在のワークツリーを優先してください。

## 最優先ルール

- 日本語で応答する。
- メモリや会話上の思い込みを根拠に実装・判断しない。
- 作業前に `README.md` と関連する仕様MDを確認し、そこに書かれた機能を正とする。
- 機能を追加・変更したら、同じ作業単位で必ずREADMEまたは仕様MDを更新する。
- テストはMDファイルの仕様・検証項目から導く。コードを見て通りそうなテストだけを選ばない。
- 「OK」「確認済み」と言うときは、何をテストしたのか、何をまだテストしていないのかを明示する。
- ビルド成功、単体テスト成功、実機起動成功だけで、ユーザーフロー完了とは言わない。

## このプロジェクトの正しい仕様ソース

- `README.md`: 現在のMVP範囲、プライバシー方針、検証手順、実機確認項目。
- 仕様MDが追加された場合: READMEと同等以上に優先し、実装前に読む。
- ソースコード: 実装状態の確認には使うが、仕様の代替にしない。

## 機能追加時の必須手順

1. READMEまたは仕様MDの該当箇所を読む。
2. 仕様が未記載なら、実装と同じ変更でMDへ追記する。
3. 実装する。
4. MDに書かれた検証項目に沿ってテストする。
5. 最終報告で、実行したコマンド、実機確認、未確認項目を分けて書く。

## DailyLangの重要仕様

- 写真はOpenAIへ送らない。今後も写真送信機能や写真送信ON/OFF設定を作らない。
- OpenAIは毎回のレッスン生成で使う。OpenAI有効/無効スイッチを作らない。
- APIキーは開発環境からKeychainへ渡される。ユーザーがアプリ内で毎回入力しないと動かない状態はバグ。
- 画像から得たキーワード、時刻、曜日、位置ラベル、ユーザーメモだけをOpenAIへ送る。
- OCRだけで物体写真を理解しようとしない。物体認識は端末内の画像解析を使う。
- 固定カテゴリーや勝手なタグで写真内容を決めつけない。
- 生成中に実際は行っていない処理名を表示しない。
- OpenAI応答が空、本文が空、保存結果が空の場合は成功扱いにしない。

## Home画面の必須仕様

- Homeには今日の通知回数、今日のレッスン数、今すぐ撮るボタンを表示する。
- Homeの最新レッスンカードには、インドネシア語例文と日本語訳を直接表示する。
- 生成後にHomeへ戻った時点で、最新レッスンの本文が見えていなければバグ。
- 詳細画面へ遷移できるだけではHome仕様を満たしたことにならない。

## Review画面と保存の必須仕様

- 生成したレッスンはSwiftDataに保存される。
- 保存済みレッスンはHomeの最新レッスンとReviewから確認できる。
- Reviewは「過去の例文を復習する」画面であり、保存済み例文が消えたように見える状態はバグとして扱う。
- 「覚えた」「もう一度」の状態変更は保存データを失わせてはいけない。
- Reviewに出ない問題を調べるときは、保存失敗、クエリ条件、ステータス絞り込み、画面更新の順に切り分ける。

## 検証ルール

READMEの `Verification` と `Before calling the MVP complete on a real iPhone` をテスト基準にする。
最低限、変更内容に応じて次を使い分ける。

```bash
swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO build -quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build/XcodeDerivedDataDevice -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO build -quiet
```

実機確認が必要な変更では、可能なら次も行う。

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

## 「テスト済み」と言ってよい条件

- MD上のどの仕様を検証したのかを言える。
- 実行したコマンドと結果を言える。
- Home、Review、LessonDetailなど画面仕様に関わる変更では、該当画面の表示確認を含める。
- OpenAI生成に関わる変更では、実リクエストまたは診断JSONで本文・単語・保存状態を確認する。
- 未確認の項目がある場合は、成功扱いにせず「未確認」と書く。

## ここまでの反省からの禁止事項

- README/仕様MDを読まずに「仕様上こうだろう」と判断しない。
- 詳細画面に表示できることを、Homeに表示できることの代わりにしない。
- SwiftData保存の一時ストア診断だけで、実アプリのHome/Reviewに残ると判断しない。
- 単体テスト成功だけで、撮影から生成、保存、Home表示、Review表示の実フローが通ったと言わない。
- 実際にAPI生成中でないのに「API生成中」と表示しない。
- 空本文、空単語、空保存を成功扱いにしない。
- ユーザーが指摘した不具合を、別の正常系テストで上書きして説明しない。

## 実装姿勢

- 最小限の変更で直す。不要な大規模リファクタリングをしない。
- 型安全性とエラーハンドリングを優先する。
- マジックナンバーは定数化する。
- コメントは「なぜ」を書く。「何を」はコードで分かるようにする。
- 秘密情報、APIキー、`.env`、credentialsは絶対にコミットしない。
