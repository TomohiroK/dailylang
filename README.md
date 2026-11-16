# DailyLang

DailyLang is a personal iOS app for turning everyday screenshots and photos into
language-learning conversations. Vision and bundled Core ML detection/classifier
models extract on-device image keywords, and lesson text is generated with
OpenAI from structured non-image scene data only.

## Working in Codex

Start repository work from the DailyLang checkout root (the directory containing
`DailyLang.xcodeproj`), and read its `AGENTS.md`.
If an existing task belongs to a different directory, explicitly select the
DailyLang working directory for commands and read the instructions applicable
to the target files. This does not change the task's project association or
filesystem permissions; use the normal scoped approval path when needed.
Do not modify another project's instructions to compensate for a wrong task root.

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
  lesson card with the selected target-language sentence and Japanese translation, and an
  immediate camera button.
- Settings lets the user choose Indonesian or English as the lesson language.
  Indonesian is the default and is also the fallback for records saved before
  this setting existed. Japanese translations and explanations remain Japanese
  for both target languages.
- The generation screen replaces the former memo field with a per-lesson
  location picker. `ランダム` is the default and resolves once per generation to
  one of: `自宅`, `友人宅`, `会社`, `学校`, `病院・動物病院`, `スーパー・コンビニ`, `デパート・モール`, `駅・空港`, `車内・機内`, `公園`,
  `お店`, `レストラン・カフェ`, or `自然の中`.
  Retired public-transport, date, out-and-about, and airport-or-port values remain readable in
  saved lessons but are excluded from the picker and random selection. Tests
  cover the new labels, both target-language payloads, and legacy decoding.
  The picker is not persisted in Settings. A specific selection is used as
  generation context, not as a device-derived current-place label, and must not
  override contradictory photo keywords.
- Local notifications scheduled at random times around a user-selected daily
  window, covering today through the next 3 days with one reservation action.
  The selected window is used for future days. A manual reservation action can
  fill today's configured count when enough time remains, and late-day manual
  reservations spread today's prompts beyond the selected end hour instead of
  compressing multiple prompts into the next few minutes.
  Reservation is reconciled per calendar day: if the user changes the daily
  count from 3 to 4 and three prompts are already scheduled for each day, the
  app adds only one prompt per day instead of replacing or duplicating all
  prompts. After scheduling, the app re-reads pending notification requests and
  reports success only when the actual pending random prompt count matches the
  expected count.
- App-launch automatic notification refresh keeps future days stocked but does
  not replenish already-delivered prompts for the current day. A notification
  that fired and disappeared from the pending queue must not be replaced by
  another immediate same-day prompt, because that creates non-stop notification
  loops.
- On app launch, delivered DailyLang capture notifications are cleared from
  Notification Center after the user has seen/opened the app, so an old stack of
  prompts does not remain on the lock screen. Pending future prompts are not
  cleared by this cleanup.
- Settings > Test Notification schedules a 5-second local notification and only
  reports success after the request is confirmed in the pending notification
  queue. The success message clears automatically after a short delay. The
  foreground app presents DailyLang notifications as banner, list, sound, and
  badge. iOS Focus modes can still suppress visible delivery, so a visible moon
  or Focus indicator is not treated as proof that scheduling failed.
- A DailyLang capture notification opens the camera when the user taps the
  notification body or its "写真を撮る" notification action. The notification
  category registers that action with the iOS foreground option so the tap path
  has an explicit app-opening route. If the app is already in the foreground
  when the notification fires, the app shows an in-app popup with a "写真を撮る"
  action instead of relying only on a system banner, because iOS may record a
  foreground notification as delivered without showing a visible banner.
- Notification diagnostics show both pending notification requests and delivered
  DailyLang notifications. Pending requests prove only that iOS accepted the
  reservation; delivered counts and the last delivery time are used to separate
  delivery failure from visual suppression.
- Settings has a debug toggle, "通知時刻を表示", that shows or hides the actual
  pending notification trigger times read back from iOS. The list is hidden by
  default and refreshes after diagnostics or notification scheduling.
- Core ML object detection first, with MobileNetV2 and Vision image
  classification as backup evidence when object labels are not enough. Camera
  photos are normalized upright before Vision processing so saliency crops use
  the same coordinate space as classification.
- Image keywords carry a role: `foreground` for subject candidates,
  `surface` for furniture or surfaces such as tables/desks, and `context` for
  background scene labels. Foreground keywords are ordered before surface and
  context keywords in the OpenAI payload.
- When object bounding boxes show a foreground item resting on a surface, the
  app sends lightweight relations such as `banana on dining table`. These are
  generated locally and do not require sending the photo.
- After image analysis, the generation screen shows editable keyword chips.
  Users can remove wrong labels or add missing foreground words before sending
  the structured scene data to OpenAI. A manually added keyword is treated as
  foreground evidence.
- OpenAI Responses API generation uses image keywords, relations, time, day,
  learner level, selected lesson language, and the location selected for that
  generation. It does not send or use a
  current-place label such as home, office, restaurant, or supermarket.
- Settings keeps the location permission action, but the manually selected
  current-place label is intentionally not available. Lesson examples must not
  be steered by a user-selected place label that can conflict with photo
  evidence.
- Learner-facing lesson surfaces show only learner-facing content: the main
  sentence, Japanese translation, vocabulary, grammar, conversation, similar
  expressions, favorite, and speech playback. Internal metadata such as image
  keywords, raw structure labels, review status, and generation
  source is not shown on Home lesson cards, Review cards, or Lesson Detail.
- Vocabulary shown in Lesson Detail must be extracted from the DUO-style main
  sentence. OpenAI may use image keywords as evidence to compose the sentence,
  but vocabulary items are saved and displayed only when their target-language text
  appears as an exact word or contiguous phrase in the main sentence. A lesson
  payload must leave enough vocabulary items for the selected learner level
  after this filtering; overly generic sparse sentences such as `Saya sedang
  belajar.` are rejected instead of being treated as successful image-based
  lessons.
- Vocabulary count is also level-specific after main-sentence filtering:
  beginner requires 3 to 5 items, intermediate requires 5 to 7 items, and
  advanced requires 7 to 10 items. OpenAI is prompted with the same level
  contract, and the app trims extra valid items before saving/displaying the
  lesson.
- Review has separate sentence and vocabulary modes. Vocabulary flash review
  is derived only from the vocabulary saved with learner-visible lessons, so it
  never introduces image keywords or words absent from a lesson main sentence.
  It groups the same normalized target-language term by lesson language,
  counts it once per saved lesson, and persists that occurrence count in a
  local SwiftData study record. New vocabulary records are always shown first.
  After the answer is revealed, `もう一度` / `難しい` / `できた` / `簡単` update the
  local FSRS-6 memory state (Difficulty, Stability, Retrievability) and the
  next review date. Only due non-new cards are shown after all new cards; ties
  use the persisted higher occurrence count first. FSRS scheduling uses the
  published default parameters without remote optimization or sync, so the
  study history stays on the device.
- `main_sentence_jp`, vocabulary meanings, grammar notes, conversation
  translations, and similar-expression translations must be learner-facing
  Japanese. If OpenAI copies target-language text into a Japanese field, omits a
  vocabulary meaning, or mixes Thai, Lao, Khmer, or Myanmar script into a
  Japanese field, the payload is rejected and retried. Records with invalid
  learner-facing text are not saved or shown on Home/Review. When any Japanese
  field fails, the repair request audits all Japanese fields together rather
  than fixing only the first rejected field and leaving another copied field
  behind.
- Prompt instructions must keep image keyword usage natural. Object labels should
  become natural actions in the selected language; they must not be forced into
  fake location phrases. Surface/context labels must not become the main topic
  when foreground keywords are available.
- For common foreground object labels, the local prompt builder supplies several
  candidate daily-life action patterns instead of a single default verb. For
  example, food can support eating, choosing, carrying, preparing, serving, or
  placing; a bottle or cup can support drinking, pouring, filling, carrying,
  serving, or placing; and books, devices, pets, plants, transport, personal
  items, people, and household objects each have multiple candidate patterns.
  These are language-generation options only: the model must choose the one
  that the current keywords, relations, and user input support, and cannot
  claim that an unobserved action happened.
- If an OpenAI response fails the lesson text/vocabulary validation, the app
  retries with the same structured scene data and an explicit repair
  instruction. Validation repairs include the previous rejected lesson JSON so
  OpenAI can preserve valid fields and correct the exact failed field instead of
  generating an unrelated lesson from scratch. A formally valid response is not retried merely because some or all
  keyword aliases are absent. If the repaired responses still fail, lesson creation is treated as
  a real error. Structural sentence checks (known untranslated image labels)
  run before Japanese-field validation because changing the target-language
  sentence can require dependent translations to change. Every
  repair request finishes with a full-payload audit for both categories. The
  initial request is followed by at most four repairs; a valid initial response
  still completes with one API request, and extra requests occur only after a
  concrete validation failure.
- Invalid vocabulary entries are discarded before saving. A single bad card
  does not discard an otherwise valid lesson when enough valid in-sentence
  vocabulary remains for the selected level. Diagnostics records the exact
  rejected field or vocabulary shortage behind `Error-1029`.
- Invalid conversation lines are also discarded when at least two coherent,
  fully translated lines remain. When regeneration is required, the exact failed
  field from the previous response is included in the repair request instead of
  sending a generic repair instruction.
- The latest lesson-generation failure reason is stored both in preferences and
  in `Library/Application Support/Diagnostics/latest-lesson-generation-failure.txt`.
  A new generation attempt does not erase the previous reason; it is cleared
  only after a valid lesson is saved successfully.
- The DUO-style main sentence is exactly one sentence in the selected language.
  The learner-level word-count targets are beginner: 7 words or fewer,
  intermediate: 10 to 15 words, and advanced: 20 to 40 words. They guide the
  generation prompt but never reject, retry, or discard an otherwise valid
  lesson. `main_sentence_word_count` records the actual count for diagnostics;
  the app does not trust a declared count instead of counting `main_sentence_id`.
  Diagnostics reports the actual word count but does not mark an otherwise valid
  lesson as blocked merely because the count is outside its target.
- To prevent a narrow pattern from becoming the default, every successfully
  saved lesson records a local, per-language/per-level grammar-focus rotation.
  The prompt cycles direct statements, current actions, completed/past actions,
  plans, purpose, sequence, cause, addition, alternatives, contrast, and
  conditions. Indonesian `sambil` / English `while` appear only in the
  parallel-action turn; Indonesian `sepertinya` / English `apparently` appear
  only in the uncertainty turn. A focus never permits inventing visual facts,
  and this internal choice is not displayed on learner-facing screens.
- A selected situation is background context rather than an instruction to
  invent an activity. In particular, selecting `自宅` or `友人宅` does not make
  household maintenance the default action. Current image evidence and the
  user note remain the primary basis for the sentence, while the prompt keeps a
  broad daily-life vocabulary palette available: food/drinks, personal items
  and tools, reading/viewing/listening, rest or social interaction, pets or
  plants, movement, and object exchange or placement. Organization and
  cleaning are one option within that range, never a forbidden-word category.
  The app locally checks the six most recent saved lessons in the same target
  language and selected situation, grouping home and friend’s home together. When a supported daily-life expression
  has recurred at least twice, only that repeated expression is sent as a soft
  diversity hint for the next generation. It remains usable when it is the
  clearest natural description of the new scene, so the hint never overrides
  the photo evidence. Inflected forms in each supported expression family count
  together, at most once per lesson; the hint contains an actually observed form.
- Vocabulary perspectives rotate independently of grammar per language and level,
  advancing only after successful lesson saving. The six perspectives are object
  details, spatial relations, handling, purpose, choice, and social exchange.
  They are soft preferences, not inferred image categories. Missing historical
  context values default to object details; existing saved lessons are unchanged.
- Generation considers three candidate sentences within the same request, ranked
  by grounding, level fit, everyday usefulness, then diversity. Only the selected
  lesson is returned. There are no additional diversity-only API retries.
- Factual descriptions use only supplied evidence. Related practice may explore
  requests, offers, intentions, wishes, questions, or conditionals involving the
  supplied objects, without claiming an unobserved action actually happened.
  Japanese translations preserve this distinction. Unknown properties (such as
  temperature or material) and missing spatial relations must not be invented.
  Conversation can carry the practical exchange when the main grammar pattern
  does not fit it; no learner-facing UI or vocabulary storage rules change.
- For Indonesian lessons, known English image labels such as `book`, `document`, `bottle`, and `cord`
  must be translated into natural Indonesian in `main_sentence_id`; the original
  labels remain only in `used_keywords`. A response that copies known English
  labels into the Indonesian sentence is repaired and, if repair is exhausted,
  is reported separately as `Error-1031`. Unknown labels are not assigned to a
  fixed category by this check.
- On-demand playback in the saved lesson's language from the lesson detail
  screen using Supertonic 3 with local ONNX Runtime inference (`id` for
  Indonesian and `en` for English).
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
- OpenAI receives the structured fields defined in `OpenAI Scene Payload` below.
- The OpenAI API key is loaded from the development environment and stored in Keychain, not entered in the app UI.

### OpenAI Scene Payload

This is the canonical list of fields in `OpenAIScenePayload.CodingKeys` in
`Sources/DailyLangCore/OpenAILessonPromptBuilder.swift`. Update this list with
any approved payload change; do not introduce separate partial allowlists in
agent instructions or historical plans.

| Field | Purpose |
| --- | --- |
| `time` | Scene time |
| `day` | Day of the week |
| `image_keywords` | On-device image labels, confidence, count, and roles, including user edits |
| `relations` | Locally inferred keyword relations |
| `user_note` | Compatibility field; the current capture flow sends an empty string and has no memo input |
| `language_level` | Selected learning level |
| `lesson_language` | Selected Indonesian or English output language |
| `situation` | Per-generation situation selection; random resolves to a concrete option |
| `lesson_pattern` | Rotating grammar/time/connector focus |
| `vocabulary_focus` | Soft rotating perspective: object details, spatial relations, handling, purpose, choice, or social exchange; never visual evidence |
| `recently_repeated_expressions` | Limited repeated-expression hints derived from local lesson history |
| `recent_vocabulary_terms` | Up to 80 deduplicated card terms from the latest 12 visible lessons in the selected language |

Do not send photo bytes, GPS coordinates, or `location_label`. Situation is
user-selected context, not a location inferred by the device. Local history
provides limited diversity hints, not a full history upload. Existing text-only
repair requests may include the rejected lesson JSON and validation feedback;
they do not authorize image or credential transmission in the prompt.

## Overlapping object labels

Generation interprets specific and broader labels (laptop/computer/device,
rice/food, plate/tableware) as potentially the same object and prefers the
specific name. This applies to arbitrary labels in both languages and all lesson
sections. Distinct objects such as laptop/phone remain usable together; explicit
separate-device evidence can justify laptop plus desktop computer. Original
keywords are retained. The diagnostic coverage helper also counts laptop/computer once; it does not
trigger generation retries. Regression checks
cover both languages, input order, retained evidence and independent objects.

## Natural expression and learner level

Photos and the selected place inspire natural language practice, rather than an
object checklist. Unused keywords are acceptable. Multiple related actions and
topics are welcome; no single-purpose formula is imposed. Avoid unrelated actions,
classifier alternatives and object enumeration added solely to fill quotas.
Advanced sentences may use 20–40 words or extend beyond this guidance naturally.
Vocabulary contains useful nouns, verbs and expressions from the actual sentence.
The selected level still controls language guidance and vocabulary schema limits.

Valid responses are returned without object-coverage or vocabulary-coverage retries.
Local alias coverage helpers are diagnostic only, not generation requirements.
Malformed content, untranslated labels and invalid Japanese still receive bounded
validation repairs. Related meetings, reports and other plausible context may be
introduced as clearly hypothetical practice, never as observed photo facts.

Regression checks cover both languages and all levels, one-request acceptance of
valid lessons with unused keywords, vocabulary selection, and retained validation.

## Verification

Vocabulary-diversity regression checks cover both languages and all learner
levels, unchanged privacy fields except the documented `vocabulary_focus`, old
SceneContext decoding, independent perspective rotation, and same-situation
history filtering (including the shared home/friend-home group). Repeated verb
inflections count once per lesson; unrelated languages/situations and records
outside the six-lesson window must not steer the hint.
For qualitative evaluation, generate repeatedly from the same food, room, shop,
outdoor, and sparse-keyword scenes, comparing vocabulary/action/exchange repeats,
unsupported claims, level fit, latency, and request counts. Prompt tests and
simulator tests do not prove improvement in live OpenAI output quality.

Choose checks for the changed behavior and its affected paths; the commands
below are options, not a mandatory sequence for every task. Widen coverage
when failures, shared behavior, additional edits, or unresolved risks require it.
Documentation-only changes need consistency, link, and diff checks, not an app
build, live API request, or device installation. Signing-only renewal needs
current signing/profile evidence and installation/launch on the actual device,
not the full lesson-generation diagnostic suite. Resolve available simulator
destinations before using a named destination from an example.

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
one manual reservation pass keeps random local notifications planned for today
through the next 3 days, spreads late-day prompts instead of clustering them
around the current minute, and refreshes future days without replenishing
delivered current-day prompts. It also checks that scheduled calendar triggers
keep seconds and time zone information and are not placed less than 60 seconds
in the future, and that user-facing reservation summaries report verified
pending counts rather than only intended counts. It also checks the
tap-to-camera notification action, diagnostic launch arguments, and
pending-notification kind classification used by the notification time debug
display.

`DailyLangCoreTests` includes OpenAI payload coverage for both Indonesian and
English that rejects numeric IDs
and prevents image keywords or related scene words from becoming vocabulary
unless the same Indonesian word or contiguous phrase appears in the generated
main sentence. It also rejects overly generic sparse lessons and lessons whose
post-filter vocabulary count is too low for the selected learner level, payloads
whose Japanese translation field is actually Indonesian text, Japanese fields
containing Thai or Lao-family script, and vocabulary meanings that merely copy
Indonesian. It also checks that the prompt payload includes keyword roles and relations while
omitting `location_label`, and that level word-count targets are encoded without
schema rejection ranges. It also
checks that the selected lesson language and situation are encoded, that English
uses the English prompt contract, and that `ランダム` resolves to a concrete
situation. It also checks that the structured prompt carries its rotating
grammar focus and that the focus options cover non-progressive time and
connector patterns.

`DailyLangTests` also checks that the OpenAI service retries when the first
response is a sparse invalid lesson, instead of silently accepting the empty or
generic result. It also checks that a non-Japanese `main_sentence_jp` and copied
vocabulary meanings are retried, that unused foreground keywords do not trigger
repair, that a sentence outside the selected level's word-count target is saved
without retry, and that validation repairs carry the rejected JSON forward,
that known English image labels are repaired into Indonesian only for an
Indonesian lesson, that an English lesson is accepted without entering that
repair branch, that failure
diagnostics survive a preferences write failure by falling back to the
diagnostics file, and that legacy corrupted records are hidden from learner-facing
Home/Review lists.

`LessonRecordPersistenceTests` verifies that Review vocabulary study derives
only from learner-visible lesson text, persists the occurrence count even when
the current aggregation is lower, places new cards before due cards, applies
the FSRS learning/relearning steps, and opens an existing lesson-only SwiftData
store after the vocabulary-study schema is added.

For local image-keyword debugging, use:

```bash
swift scripts/run-image-keyword-check.swift <image> [<image> ...]
swift scripts/run-image-keyword-check.swift --expected tests/golden/expected.json <image> [<image> ...]
```

The script applies the same orientation normalization, keyword thresholding,
role assignment, label cleanup, and relation extraction as the app path. Its
output includes `foreground` / `surface` / `context` roles and `RELATIONS`. When
an expected JSON is supplied, each key is an image file name or path and each
value is either an array of expected foreground labels or
`{"foreground": ["banana", "cup"]}`; the script reports foreground recall@10
and foreground noise rate.

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
`com.tomohirok.dailylang`.

### First Device Setup

- Add an Apple ID in Xcode > Settings > Accounts.
- Use an existing valid Apple Development identity with its private key;
  create one through Manage Certificates only if needed and authorized.
- Connect the iPhone by USB, unlock it, and trust this Mac.
- Enable Developer Mode on the iPhone if iOS asks for it.
- In target DailyLang > Signing & Capabilities, choose a Team.
- If the selected Team cannot use the existing bundle identifier, resolve the
  ownership mismatch. Do not silently change the identifier: it can separate
  installed app data and Keychain access from the existing app.

### Renew an Existing Installation

- A request to renew/reinstall authorizes the normal scoped signing, profile
  renewal, installation, and launch for the existing app and Team. Do not ask
  for the same authorization at every step; filesystem/tool permissions still
  apply. It does not authorize account removal, certificate revocation, a new
  Team or bundle identifier, app deletion, or API key changes.
- Check the connected device and current signing identity first. Unlock the
  iPhone, confirm trust and Developer Mode as needed, and resolve an explicit
  device-locked error before inferring SDK incompatibility.
- Inspect the app's embedded provisioning profile and certificate expiration
  separately. An expired installation does not by itself prove the certificate
  must be recreated, and multiple certificates alone do not prove a conflict.
- Rebuild with the existing valid identity and automatic provisioning updates,
  then install over the existing app without deleting its data. Verify the new
  embedded profile's expiry and actual launch on the connected iPhone.
- If renewal fails, retain the first signing/provisioning error and distinguish
  missing private key, profile/certificate mismatch, device registration,
  account access, and network failures. Account reset or certificate revocation
  is a separate recovery action requiring evidence and specific authorization.

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

For app behavior changes, use Settings > On-device Diagnostics as supporting
evidence and verify the affected camera, location, generation, persistence,
notification, or playback flow directly on the same device. For signing-only
renewal, installation and launch checks are sufficient for that scope; do not
claim the other features were retested.

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
context, the latest lesson-generation failure reason, the real image-to-lesson
OpenAI request path using the selected lesson language, a random diagnostic
location, and learner level with its main sentence word count and vocabulary count, and Supertonic
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
- In Settings > Learning, select Indonesian and English in turn and confirm a
  newly created lesson uses the selected language while keeping Japanese
  translations and explanations. Existing records created before this setting
  must continue to behave as Indonesian lessons.
- After taking a photo, select a specific location in the generation screen and
  confirm the new main sentence reflects it without contradicting the image
  keywords. With `ランダム`, confirm the saved generation context resolves to one
  concrete location rather than sending a device-derived current-place label.
- From Home, take a real photo and confirm that returning from the generation
  sheet leaves the latest lesson text visible on Home. The latest card must show
  both the selected target-language sentence and Japanese translation before the user opens
  Lesson Detail.
- After creating a lesson, open Review and confirm the saved example is visible
  there. Marking it as remembered must not make the saved example disappear from
  Review.
- After creating at least two saved lessons that share a vocabulary item, open
  Review > 単語. Confirm the flash cards contain only vocabulary from saved
  main sentences, show the Japanese meaning before reveal, and display the
  shared word with its combined lesson frequency. Confirm newly registered
  vocabulary appears before due vocabulary; reveal one answer and select each
  of `もう一度` / `難しい` / `できた` / `簡単` on separate cards, then close and reopen
  Review to confirm the selected card is hidden until its scheduled review time
  while the saved lesson itself remains available.
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
  > Test Notification to send a prompt after 5 seconds. Tapping a delivered
  notification body or the "写真を撮る" notification action must open the camera
  only after the app is active; it must not crash during app foregrounding.
- Lesson Detail must not show Thai/Lao/Khmer/Myanmar characters in Japanese
  translations, and vocabulary cards must show Japanese meanings rather than
  copied target-language words.
- OpenAI generation on every real lesson; Settings does not contain an OpenAI
  enable/disable switch.
- Supertonic speaker playback from Lesson Detail, after the Settings voice test
  works on the same device.

## Situation-based action associations

Lesson generation now includes an open-ended action palette for every selectable place: office work and meetings, shopping and browsing, restaurant dining and ordering, school study and note-taking, and everyday activities for the other locations. The model combines relevant actions with photo keywords and adapts expressions to the selected language, level, and sentence pattern. These suggestions do not change detected keywords or introduce coverage requirements. Unobserved actions must be explicit wishes, plans, requests, or questions; observed-action patterns still require evidence.

## Recent vocabulary as generation input

`recent_vocabulary_terms` is an additional OpenAI Scene Payload field containing
up to 80 deduplicated card terms from the most recent 12 learner-visible lessons
in the selected language, across situations. Only target-language terms are sent;
no photos, past sentences, Japanese translations or record identifiers are added.
Generation chooses level-appropriate teaching expressions before composing the
sentence and treats recent cards as familiar rather than new learning targets.
Common words remain usable; no novelty quota or extra retry is imposed. Advanced
cards favor useful phrases and collocations over a recurring inventory of objects.
Japanese translation instructions explicitly audit every clause and state.

Validation covers language isolation, recency, deduplication, context compatibility
and propagation into the request. These deterministic checks do not prove model
output diversity or semantic translation completeness; live generations are a
separate quality check.
