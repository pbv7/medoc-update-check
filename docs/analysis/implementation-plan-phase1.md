# Implementation Plan — Phase 1 (2-Marker Refactor)

Summary of the refactor from a 3-flag model to the 2-marker model used in code and tests.

## Goals

- Replace flag-based validation with marker-based validation (Version + Completion).
- Improve testability with focused helper functions.
- Keep return shapes and Event IDs consistent and minimal.

## Key Helpers (Public)

- **Find-UpdateLogFile** — Discovers the update log file, supporting both
  legacy `update_YYYY-MM-DD.log` and multi-phase `update=PID_YYYY-MM-DD.log`
  formats with fallback.
- **Find-LastUpdateOperation** — Extracts the last operation block from the discovered update log.
- **Test-UpdateMarker** — Checks marker presence inside an operation block:
  - VersionConfirm (V): `Версія програми - {TARGET_VERSION}`
  - CompletionMarker (C): `Завершення роботи, операція "Оновлення"`
- **Test-UpdateState** — Orchestrates marker classification over the last operation:
  - Status: Success/Failed
  - VersionConfirm, CompletionMarker, OperationFound, Message

## Core Function Behavior

- **Test-UpdateOperationSuccess**
  - Detects update trigger in Planner.log (4-digit year).
  - Reads corresponding update log via `Find-UpdateLogFile` (`update_YYYY-MM-DD.log` or multi-phase `update=PID_YYYY-MM-DD.log`, 2-digit year).
  - Uses `Test-UpdateState` to classify:
    - Success: both markers present.
    - Failed: missing version marker, missing completion marker, or missing update log (both naming formats checked).
    - NoUpdate: no update trigger in Planner.log.
  - Return shape includes: Status, ErrorId, Success (bool), versions, timestamps, MarkerVersionConfirm, MarkerCompletionMarker, OperationFound, Reason.

- **Format-UpdateTelegramMessage / Format-UpdateEventLogMessage**
  - Report Success/Failed/NoUpdate with marker-based reasons (no 3-flag details).

- **Invoke-MedocUpdateCheck**
  - Maps outcomes to Event IDs:
    - Success → 1000
    - NoUpdate → 1001
    - Failed (validation) → 1302
    - Errors (config/fs/encoding/telegram) → respective ranges

## What Changed from 3-Flag Model

- Removed dependence on infrastructure/restart flags; only markers V and C matter.
- Unified failures under `UpdateValidationFailed` (1302) for marker issues.
- Return properties renamed to marker-based (`MarkerVersionConfirm`, `MarkerCompletionMarker`, `OperationFound`).
- Failure messaging focuses on which marker(s) are missing, not per-flag status.

## Testing Approach

- Unit coverage for helper functions (operation extraction, marker detection, classification).
- Scenario coverage with Windows-1251 fixtures:
  - Success (both markers)
  - Missing version marker
  - Missing completion marker / incomplete block
  - No update trigger
  - Missing update log (both `update_YYYY-MM-DD.log` and `update=PID_YYYY-MM-DD.log`)
- Encoding error handling validated via mocked Get-Content failures.
