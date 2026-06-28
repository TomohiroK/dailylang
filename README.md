# DailyLang

DailyLang is a personal iOS app for turning everyday screenshots and photos into
language-learning conversations. Vision and bundled Core ML detection/classifier
models extract on-device image keywords, and lesson text is generated with
OpenAI from structured non-image scene data only.

## Goals

- Keep photos local and never send image data to OpenAI.
- Separate reusable language logic from iOS UI code.
- Make image keyword extraction and conversation generation independently testable.

## Structure

- `DailyLangApp/` - SwiftUI iOS application source.
- `Sources/DailyLangCore/` - reusable prompt, lesson, and scene data logic.
- `Tests/DailyLangCoreTests/` - tests for prompt construction and fallback generation.

## MVP Scope

- Home, camera capture, generation, lesson detail, review, and settings screens.
- Home shows today's notification count, today's lesson count, a visible latest
  lesson card with the Indonesian sentence and Japanese translation, and an
  immediate camera button.
- Local notifications scheduled at random times around a user-selected daily
  window, covering today through the next 3 days with one reservation action.
  The selected window is used for future days. The current day still schedules
  the configured count even if the reservation happens after the selected end
  hour, because a day set to 4 notifications must produce 4 notification
  requests for that day.
  Reservation is reconciled per calendar day: if the user changes the daily
  count from 3 to 4 and three prompts are already scheduled for each day, the
  app adds only one prompt per day instead of replacing or duplicating all
  prompts. After scheduling, the app re-reads pending notification requests and
  reports success only when the actual pending random prompt count matches the
  expected count.
- Settings > Test Notification schedules a 5-second local notification and only
  reports success after the request is confirmed in the pending notification
  queue. The success message clears automatically after a short delay. The
  foreground app presents DailyLang notifications as banner, list, sound, and
  badge. iOS Focus modes can still suppress visible delivery, so a visible moon
  or Focus indicator is not treated as proof that scheduling failed.
- A DailyLang capture notification opens the camera when the user taps it. If
  the app is already in the foreground when the notification fires, the app
  shows an in-app popup with a "写真を撮る" action instead of relying only on a
  system banner, because iOS may record a foreground notification as delivered
  without showing a visible banner.
- Notification diagnostics show both pending notification requests and delivered
  DailyLang notifications. Pending requests prove only that iOS accepted the
  reservation; delivered counts and the last delivery time are used to separate
  delivery failure from visual suppression.
- Settings has a debug toggle, "通知時刻を表示", that shows or hides the actual
  pending notification trigger times read back from iOS. The list is hidden by
  default and refreshes after diagnostics or notification scheduling.
- Core ML object detection first, with MobileNetV2 and Vision image
  classification as backup evidence when object labels are not enough.
- OpenAI Responses API generation using image keywords, time,
  location label, and optional user note.
- Location permission is used for lightweight on-device context only: moving
  fast enough becomes `road`; otherwise the user-selected current place label is
  used. Permission alone does not infer home, office, restaurant, or supermarket
  from coordinates.
- Learner-facing lesson surfaces show only learner-facing content: the main
  sentence, Japanese translation, vocabulary, grammar, conversation, similar
  expressions, favorite, and speech playback. Internal metadata such as image
  keywords, raw structure labels, location label, review status, and generation
  source is not shown on Home lesson cards, Review cards, or Lesson Detail.
- Vocabulary shown in Lesson Detail must be extracted from the DUO-style main
  sentence. OpenAI may use image keywords as evidence to compose the sentence,
  but vocabulary items are saved and displayed only when their Indonesian text
  appears as an exact word or contiguous phrase in the main sentence. A lesson
  payload must leave at least 4 vocabulary items after this filtering; overly
  generic sparse sentences such as `Saya sedang belajar.` are rejected instead
  of being treated as successful image-based lessons.
- `main_sentence_jp` must contain a Japanese translation. If OpenAI copies the
  Indonesian sentence into `main_sentence_jp`, the payload is rejected and the
  app retries once. Records with non-Japanese translation text are not shown on
  Home or Review.
- Prompt instructions must keep image keyword usage natural. Object labels should
  become actions such as `menggunakan keyboard`, `membaca dokumen`, or
  `makan pisang`; they must not be forced into fake location phrases such as
  `di keyboard`.
- If an OpenAI response fails the lesson text/vocabulary validation, the app
  retries once with the same structured scene data and an explicit repair
  instruction. If the repaired response still fails, lesson creation is treated
  as a real error.
- On-demand Indonesian sentence playback from the lesson detail screen using
  Supertonic 3 with local ONNX Runtime inference.
- Review shows saved lesson sentences for recall practice. Marking a lesson as
  remembered or again updates review status but must not hide or delete the
  saved lesson from Review.
- SwiftData local persistence uses the explicit app-local store file
  `Application Support/DailyLangLessons.store` so Home, Review, generation, and
  diagnostics read the same saved lessons. Login, sharing, cloud DB, and
  Firebase are intentionally excluded.
- The generation screen treats a SwiftData `save()` error or empty lesson text
  as failure, but it does not block the user on an immediate post-save fetch
  false negative. Persistent readback is verified separately by the Xcode
  persistence tests and the `save-roundtrip` diagnostic.

## Supertonic Assets

Supertonic source and model assets are local development dependencies and are
ignored by Git because the ONNX models are large.

```bash
git clone --depth 1 https://github.com/supertone-inc/supertonic.git Vendor/supertonic
git lfs install
git clone --depth 1 https://huggingface.co/Supertone/supertonic-3 Vendor/SupertonicAssets
```

The app bundle uses `Vendor/SupertonicAssets/onnx` and
`Vendor/SupertonicAssets/voice_styles` as folder resources. The copied helper
code is from Supertonic's Swift example under the MIT license; see
`ThirdPartyNotices/Supertonic-LICENSE`.

## Privacy Defaults

- Photos are not saved unless the user turns on photo saving.
- Photos are never sent to OpenAI.
- OpenAI receives only structured scene data: time, day, location label, image keywords, user note, and level.
- The OpenAI API key is loaded from the development environment and stored in Keychain, not entered in the app UI.

## Verification

```bash
swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator -typecheck DailyLangApp/**/*.swift Sources/DailyLangCore/*.swift -parse-as-library
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -resolvePackageDependencies -project DailyLang.xcodeproj -scheme DailyLang -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/SourcePackages
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO test -quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO build -quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DailyLang.xcodeproj -scheme DailyLang -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build/XcodeDerivedDataDevice -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGNING_ALLOWED=NO build -quiet
```

The iOS app target is available at `DailyLang.xcodeproj`. Build it with Xcode
after the matching iOS platform is installed.

`DailyLangTests` includes notification scheduler coverage for the MVP rule that
one reservation pass keeps random local notifications planned for today through
the next 3 days, keeps the configured count for the current day even after the
selected end hour, and refreshes when fewer than two days of prompts remain. It
also checks that scheduled calendar triggers keep seconds and time zone
information and are not placed less than 60 seconds in the future, and that
user-facing reservation summaries report verified pending counts rather than
only intended counts. It also checks the diagnostic launch arguments and
pending-notification kind classification used by the notification time debug
display.

`DailyLangCoreTests` includes OpenAI payload coverage that rejects numeric IDs
and prevents image keywords or related scene words from becoming vocabulary
unless the same Indonesian word or contiguous phrase appears in the generated
main sentence. It also rejects overly generic sparse lessons that cannot support
at least 4 vocabulary items from the main sentence, and rejects payloads whose
Japanese translation field is actually Indonesian text.

`DailyLangTests` also checks that the OpenAI service retries once when the first
response is a sparse invalid lesson, instead of silently accepting the empty or
generic result. It also checks that a non-Japanese `main_sentence_jp` is retried
and that legacy corrupted records are hidden from learner-facing Home/Review
lists.

## Real Device Setup

Open the project in Xcode before real-device testing:

```bash
open -a Xcode DailyLang.xcodeproj
```

Then confirm the Mac-side prerequisites:

```bash
bash scripts/check-ios-device-readiness.sh
```

Do not start a real-device install while `Code signing identities` says
`0 valid identities found`. `scripts/run-ios-device.sh` stops early in that
state because the build can otherwise spend time compiling and then fail at the
final CodeSign step with `errSecInternalComponent`.

The app target uses automatic signing with bundle identifier
`com.tomohirok.dailylang`. For a first real-device run:

- Add an Apple ID in Xcode > Settings > Accounts.
- Create an Apple Development certificate from Manage Certificates.
- If Keychain or Xcode credentials are stale, remove the invalid account entry
  from Xcode Settings > Accounts, add it again, then create the certificate.
- Connect the iPhone by USB, unlock it, and trust this Mac.
- Enable Developer Mode on the iPhone if iOS asks for it.
- In target DailyLang > Signing & Capabilities, choose a Team.
- If the bundle identifier is already taken for the selected team, change it to
  a personal development identifier such as `com.tomohirok.dailylang.dev`.

Once the iPhone appears in `bash scripts/check-ios-device-readiness.sh`, build,
install, and launch the app into Settings diagnostics:

```bash
scripts/run-ios-device.sh <device-udid>
```

If Xcode has not saved a Team in the project yet, pass it explicitly:

```bash
DEVELOPMENT_TEAM=<team-id> scripts/run-ios-device.sh <device-udid>
```

The script uses automatic signing and `-allowProvisioningUpdates` by default.
Set `ALLOW_PROVISIONING_UPDATES=0` to disable that, or
`ALLOW_DEVICE_REGISTRATION=1` if the device needs to be registered through the
developer account. It launches with `-DailyLangOpenSettings` unless other launch
arguments are provided.

After the app launches on the iPhone, start with Settings > On-device
Diagnostics, then verify camera capture, location status, image keywords,
notification scheduling, and Supertonic playback on the same device.

For simulator smoke testing, install and launch the app, then trigger the local
sample scene with a launch argument:

```bash
xcrun simctl launch booted com.tomohirok.dailylang -DailyLangSampleScene
```

The sample path uses the same on-device image keyword extraction, OpenAI
generation, and SwiftData saving pipeline as a captured photo.

For repeatable real-device diagnostics, launch with the export argument and
copy the generated JSON from the app container:

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

To verify notification scheduling without tapping the Settings UI, launch with
the scheduling argument before exporting diagnostics:

```bash
ALLOW_DEVICE_REGISTRATION=1 scripts/run-ios-device.sh <device-udid> \
  -DailyLangScheduleRandomNotifications \
  -DailyLangExportDiagnostics
```

The exported JSON then includes both the normal `notifications` item and a
`launch-schedule-random-notifications` item. The launch item is `ready` only
when scheduling completed and the scheduler verified the actual pending random
prompt count. For the 5-second test notification, use
`-DailyLangScheduleTestNotification`; because it can fire before a full export
finishes, use it to verify that `center.add` and pending confirmation succeeded,
not as the durable pending-count proof.

For screenshot or manual UI checks of the Settings notification list, add
`-DailyLangOpenSettings -DailyLangShowNotificationTimes` to open Settings with
the pending notification time list visible. Use `-DailyLangHideNotificationTimes`
to reset the debug list to hidden.

The export includes camera, location, notification, OpenAI key availability,
privacy default, Supertonic asset, image keyword input generation, persistent
saved lesson count, a save-readback round trip in the app's real SwiftData
context, the real image-to-lesson OpenAI request path, and Supertonic
WAV-generation readiness. It does not play audio; audible playback is
intentionally tied to the user pressing a voice button in the app.

Before calling the MVP complete on a real iPhone, verify:

- Settings > On-device Diagnostics shows camera, location, notifications,
  OpenAI key availability, privacy defaults, Supertonic, and image keyword input
  readiness. The input check runs a generated sample image through on-device
  object detection and image classification, then confirms the structured data
  path used for the API. The notification item must show the number of pending
  random prompts, pending test prompts, delivered random/test notifications, the
  next trigger time, the latest delivery time, authorization, alert, sound,
  notification center, lock screen, scheduled summary, and time-sensitive
  settings. Pending requests alone do not prove that a notification fired; when
  a notification is expected at a specific time, re-check delivered counts after
  that time. The item is not ready merely because pending requests exist; hidden
  delivery settings must be treated as a warning. The `stored-lessons` item must show the app's real
  saved lesson count, and `save-roundtrip` must be ready because it uses the
  app's real SwiftData context, saves a diagnostic record, reads it back by ID,
  and removes it again. Re-run diagnostics after changing iOS Settings
  permissions.
- In Settings > On-device Diagnostics, tap Create Sample Lesson to run the
  same on-device sample through image keywords, OpenAI generation, SwiftData
  persistence, and Lesson Detail display.
- From Home, take a real photo and confirm that returning from the generation
  sheet leaves the latest lesson text visible on Home. The latest card must show
  both the Indonesian sentence and Japanese translation before the user opens
  Lesson Detail.
- After creating a lesson, open Review and confirm the saved example is visible
  there. Marking it as remembered must not make the saved example disappear from
  Review.
- After creating a lesson, confirm Settings > On-device Diagnostics shows
  `stored-lessons` greater than 0. Export diagnostics can provide the same
  evidence when `devicectl` is working, but the in-app Settings diagnostic is
  the primary device-side proof.
- In Settings > On-device Diagnostics, tap Play Voice Test to verify
  Supertonic ONNX initialization, WAV generation, and on-device playback before
  testing Lesson Detail.
- Camera permission and real camera capture.
- Camera denial recovery from the app's Settings shortcut.
- On-device object detection and image classification on a real captured photo.
- Notification permission, scheduling, and tap-to-camera launch. Use Settings
  > Test Notification to send a prompt after 5 seconds.
- OpenAI generation on every real lesson; Settings does not contain an OpenAI
  enable/disable switch.
- Supertonic speaker playback from Lesson Detail, after the Settings voice test
  works on the same device.
