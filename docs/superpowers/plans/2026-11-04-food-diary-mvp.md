# Food Diary MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. User requested direct implementation and physical iPhone validation.

**Goal:** Deliver a usable Chinese iPhone food diary with editable DeepSeek text/photo estimates and persistent daily totals.

**Architecture:** SwiftUI owns presentation and main-actor UI state. A local NutritionCore package owns validated value models, atomic persistence, and the typed DeepSeek request/response boundary. Keychain stores the personal API key.

**Tech Stack:** Swift 6, SwiftUI, iOS 26, Foundation, URLSession, PhotosUI, UIKit camera, Security, Swift Testing.

**Spec:** docs/superpowers/specs/2026-11-04-food-diary-mvp.md

## Global Constraints

- iPhone, Simplified Chinese, iOS 26 minimum.
- Real iPhone validation as requested, use generic iOS compilation before connection.
- API key only in Keychain, excluded from logs and data exports.
- Persist only explicitly confirmed records. Atomic write before in-memory mutation.
- Original files survive decode errors. All AI nutrition values labeled estimates.
- Default deepseek-flash with image_url content and JSON output, disabled thinking for latency.
- Empty install contains no sample meals. Manual entry works without an API key.

## Review Focus

- Invalid numeric AI values, empty food lists and truncated JSON must be rejected.
- Read or write failure must not erase previous data or discard an editable draft.
- Changing date, portion or meal must propagate to totals and persisted data.
- Cancelled/stale network and photo-loading tasks must not overwrite newer input.
- API errors must surface safely, and keys must never enter logs or diary files.

### Task 1 — Models and storage

Files are Package.swift, Sources/NutritionCore/Models.swift, DiaryStore.swift and Tests/NutritionCoreTests/DiaryTests.swift.

Interfaces are FoodItem.nutrition, FoodItem.validate(), MealRecord.validate(), DiaryStore.load(), DiaryStore.save(_:), and DiaryDocument.

- [ ] Write failing tests for scaling, invalid input, JSON round-trip, update/delete and corrupt-file protection.
- [ ] Run the tests to confirm the missing implementation fails, implement the model/storage boundary, then run the full package suite.

### Task 2 — DeepSeek analysis

Files are Sources/NutritionCore/DeepSeekClient.swift and Tests/NutritionCoreTests/DeepSeekTests.swift.

Interfaces are DeepSeekClient.makeRequest(text:imageJPEG:apiKey:model:), DeepSeekClient.parseResponse(data:statusCode:), and DeepSeekClient.analyze(text:imageJPEG:apiKey:model:).

- [ ] Write failing tests for multimodal request encoding, authentication validation, structured response parsing, provider errors, blank/truncated output and invalid nutrition.
- [ ] Confirm failures, implement the real request/response boundary, then run the complete package suite.

### Task 3 — Native application

Files are FoodDiary.xcodeproj, FoodDiary/App, FoodDiary/Features, FoodDiary/Services and FoodDiary/Assets.xcassets.

Consumes NutritionCore models, storage and client. Produces native today, composer/editor, trend and settings screens.

- [ ] Build the app structure around the tested core with Keychain, camera/photo picking, cancellable analysis and manual fallback.
- [ ] Compile for generic iOS with xcodebuild, inspect all warnings and errors, and fix failures.
- [ ] Perform a full code review and run the package suite again.

### Task 4 — Physical validation and handoff

Files are README.md and work/validation.md.

- [ ] Request iPhone connection when installation is ready, inspect pairing and signing, and deploy when available.
- [ ] On iPhone verify manual save, edit, delete, date change and restart persistence, then verify live DeepSeek if user key is configured.
- [ ] Document verified outcomes and any exact remaining device/account dependency.
