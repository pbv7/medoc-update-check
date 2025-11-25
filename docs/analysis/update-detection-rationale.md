# Update Detection Rationale

This document captures the reasoning behind the 2-marker validation model for M.E.Doc updates.

## Core Markers (Both Required)

- **Marker V (Version):** `Версія програми - {NUMBER}` confirms the target version was applied.
- **Marker C (Completion):** `Завершення роботи, операція "Оновлення"` confirms the operation finished.

## Classification

- ✅ **Success:** V present AND C present.
- ❌ **Failed:** Missing V or C (includes incomplete/aborted operations).
- ℹ️ **NoUpdate:** Planner.log contains no update trigger to evaluate.

## Search Strategy (Last Operation Only)

1. Search backward in `update_*.log` for the completion marker (C).
2. From that point, search backward for the start marker (`Початок роботи, операція "Оновлення"`).
3. Extract the block between start/end markers and evaluate markers V and C inside that block.
4. If completion marker is missing → Failed (operation incomplete).
5. Earlier operations are ignored; only the last operation is evaluated.

## Why Two Markers

- Version-only without completion ⇒ may be partial/rolled back.
- Completion-only without version ⇒ update didn’t actually land.
- Both together reliably indicate a finished, version-correct update.

## Encoding and Timestamps

- Logs use Windows-1251 (Cyrillic). Wrong encoding yields false negatives → treat as `EncodingError`.
- Planner timestamps use 4-digit year (`dd.MM.yyyy`); update logs use 2-digit year (`dd.MM.yy`).

## Event IDs (Relevant Range)

- **1000** Success — both markers present.
- **1001** NoUpdate — no update trigger/operation to evaluate.
- **1204** EncodingError — failed to read logs with configured encoding.
- **1302** UpdateValidationFailed — missing version or completion marker (including incomplete operations).

## Outcomes in Practice

- **Success:** Both markers found in last operation block.
- **Failed:** Any marker missing in the last operation block, or update log missing.
- **NoUpdate:** No update trigger found in Planner.log (nothing to evaluate).*** End Patch
