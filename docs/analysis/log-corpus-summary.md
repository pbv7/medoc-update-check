# Log Corpus Summary (Manual Review)

Snapshot of the manual corpus analysis that informed the 2-marker model.

- **Total logs analyzed:** 101 (1 unreadable)
- **Date range:** 2023-04-01 to 2025-11-04
- **Encoding:** Windows-1251 (Cyrillic); wrong encoding produces false negatives.

## Classification Counts

| Category | Count | Notes |
|----------|-------|-------|
| SUCCESS | 50 | Both markers present (version + completion) |
| FAILED | 26 | Missing markers with errors present |
| INCOMPLETE | 24 | Missing markers, no errors (treated as Failed in implementation) |
| TOTAL | 100\* | *Plus 1 unreadable file* |

## Observations

- Successful logs consistently show both markers near the end of the file.
- Completion-only without version, or version-only without completion, correlates with failed or incomplete updates.
- No-update cases simply lack the update trigger in Planner.log and have no corresponding update log.

## How It Informed the Design

- Led to the 2-marker requirement: both markers must be present for Success.
- Missing either marker → Failed (covers incomplete/aborted scenarios).
- Reinforced the need for backward search to evaluate only the last operation.
- Highlighted encoding sensitivity; encoding errors are surfaced explicitly (EncodingError).
