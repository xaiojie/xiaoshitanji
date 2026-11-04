# Labels and Smoking Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. User authorized direct continuation.

**Goal:** Prefer photographed nutrition labels for products, improve bowl-specific estimates, and deliver a usable smoking/inventory journal.
**Architecture:** Extend the existing compatible JSON document. Calculate nutrition and inventory deterministically in NutritionCore, reuse DeepSeek transport and existing image preparation, keep confirmation and mutations local.
**Tech Stack:** Swift 6, SwiftUI, Charts, PhotosUI, iOS 26 Liquid Glass.
**Spec:** docs/superpowers/specs/2026-11-04-labels-and-smoking.md

## Global Constraints

- Physical iPhone only, no Simulator.
- Older schema-1 JSON remains readable.
- Save document atomically before replacing observed state.
- Nicotine label yield is distinct from actual absorption, unknown values remain optional.
- Prices and nicotine values require visible evidence or explicit user input.

## Review Focus

- Labels per serving, package, grams and milliliters cannot be mixed or use NRV percentages as grams.
- Existing and refined label-derived foods retain deterministic totals and scaling.
- Sharing and calibration cannot increase personal nicotine totals.
- Switching packs, undoing events and empty stock must preserve consistent per-pack inventory.
- Failed/cancelled photo analysis must retain editable user input and cannot silently apply stale results.

### Task 1 — Nutrition label support

- [x] Tests for kJ/kcal and per100mL/per-serving calculations, portion scaling, legacy decode and API prompt/parse.
- [x] Implement NutritionLabel and input mode, add optional fields to existing food/meal models, update DeepSeek mapping and prompts.
- [x] Wire mode picker and readable source/basis cards into existing composer and portion view. Compile iPhone.

### Task 2 — Smoking journal

- [x] Tests for pack opening, smoking/sharing, calibration, undo, invalid stock, dates, unknown values and persistence.
- [x] Implement SmokingDiary, pack/product snapshots and event validation, extend DiaryDocument and DiaryModel mutations.
- [x] Implement evidence-bound cigarette photo request and response parsing, test failure conditions.
- [x] Build smoking dashboard, pack editor with photo/AI confirmation, share/calibration sheets and history routes. Compile iPhone.

### Task 3 — Verify and deliver

- [x] Full core tests, final read-only review, signed Debug/Release builds, version and export descriptions.
- [ ] Install and verify on connected iPhone when available, report remaining device-dependent checks accurately.
