# AI First Food Diary Redesign Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. User requested continued design and development directly. Physical-device runtime verification is deferred until reconnection.

**Goal:** Deliver a richer nutrition dashboard and AI-driven food logging without requiring weighed food or nutrient entry.

**Architecture:** Reuse NutritionCore and the existing SwiftUI app. Add backward-compatible portion metadata, typed refinement/review requests and persisted daily reviews. Split presentation into focused native view components.

**Tech Stack:** Swift 6, SwiftUI, Charts, iOS 26 Liquid Glass, DeepSeek chat completions and existing Keychain/atomic JSON storage.

**Spec:** docs/superpowers/specs/2026-11-04-ai-first-redesign.md

## Global Constraints

- All analysis is initiated by an explicit user action with the configured Keychain key.
- Daily user flow accepts natural portions and photos. Keep estimated grams internal.
- Decode existing schemaVersion 1 records and preserve saved meal identities.
- Use only actual stored records for charts and AI reviews. Empty and unscored states remain explicit.
- Validate review snapshots before persistence and invalidate reviews when relevant records change.
- Build for physical iPhone SDK. Runtime validation requires the user's connected phone.

## Review Focus

- Old JSON missing new portion/review fields must remain readable.
- Applying a portion multiplier repeatedly must use a clearly stated current portion and finite positive numbers.
- A refinement must include existing foods and correction history and must not compound prior corrections twice.
- Cancelled requests, changed dates and edited food snapshots must not overwrite newer state.
- AI review scores require valid bounds and must remain absent when returned as null.

### Task 1 — AI data and backward compatibility

Files are Models.swift, DietReview.swift and DiaryTests.swift. Add failing tests for natural portions, legacy payloads, portion scaling and review invalidation, then implement and run the core suite.

### Task 2 — Refinement and daily analysis

Files are DeepSeekClient.swift and DeepSeekTests.swift. Add failing tests for provider request context, portion parsing and review response validation. Implement typed client entry points using the existing transport, then run the full suite.

### Task 3 — Native interface

Replace numerical food entry with natural-language correction and portion controls. Build dashboard cards, four meal slots, an AI review detail sheet and weekly charts. Reuse camera, photo preprocessing, Keychain and atomic save. Run the iPhone Debug build after each major screen.

### Task 4 — Verification and handoff

Run all tests, independent read-only code review, iPhone Debug and Release builds. Update the usage guide and record exact verification boundaries. Prepare the signed build for the next physical-device installation.
