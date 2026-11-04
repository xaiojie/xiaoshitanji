# Personal Health Hub Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. The user has authorized direct implementation and connected iPhone updates.

**Goal:** Replace the settings-only profile tab with an editable personal health hub and move infrastructure preferences into General Settings.

**Architecture:** Extend NutritionCore's existing versioned document with a validated profile and manual weight history. Keep Apple Health read-only data in a root-owned observable service. Reuse existing photo processing, cards, persistence and native navigation.

**Tech Stack:** Swift 6, SwiftUI, Charts, PhotosUI, HealthKit, atomic JSON, Keychain and iOS 26 Liquid Glass.

**Spec:** docs/superpowers/specs/2026-11-04-personal-health.md

## Global Constraints

- Persist only confirmed profile/measurement changes and keep existing schema-1 diaries readable.
- Derive BMI from actual height/weight with explicit metric units and optional missing values.
- Read only requested HealthKit types and request authorization through an explicit in-app action.
- Missing or unshared health readings remain nil. Health authorization completion cannot reveal individual read permission status.
- Keep DeepSeek keys in the existing Keychain service and limit health/profile data to local display.
- Use the existing physical-iPhone build and installation workflow.

## Review Focus

- Invalid/blank height, weight or target must not cause nonfinite BMI or erase history.
- Changing only avatar/nickname must not create a duplicate current weight.
- Older profile drafts must not overwrite newer measurements returned during editing.
- Manual and HealthKit values need dates and source labels with a consistent latest-reading policy.
- Refresh failures and partial/missing data must not become fabricated zero activity.

### Task 1 — Models and persistence

Write failing tests for profile/BMI, manual weight history and legacy document decoding, then extend HealthProfile.swift, Models.swift and DiaryModel.swift. Reuse the existing atomic DiaryStore.

### Task 2 — Apple Health reader

Verify capability provisioning, add the read-only authorization and 7-day activity queries, body-weight samples and latest height. Keep query conversion and UI state explicit, and compile for iPhone.

### Task 3 — Native health views

Build My Health header/editor, today/ability/all-data sections, weight logging/detail and General Settings. Reuse native navigation and existing content surfaces. Run iPhone builds as each entry point is wired.

### Task 4 — Verification and installation

Run the full core suite, read-only review, signed iPhone build and device installation. Verify installed version and report any exact user-dependent authorization or launch step.
