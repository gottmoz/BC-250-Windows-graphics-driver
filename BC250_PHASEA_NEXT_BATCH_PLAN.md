# BC-250 Phase A: Next Batch Plan

Last updated: 2026-05-01 17:30 (Europe/Stockholm)

## Current verified state
- Latest Phase A run file: `tools/phaseA-run-20260501-171833.log`
- Signed package install succeeds (`devcon update` + service creation).
- Driver activation still fails and falls back to:
  - `display.inf`
  - `CM_PROB_FAILED_POST_START` (Code 43)
- No-reboot guarded flow works and keeps machine recoverable.

## Error-code focus
1. `CM_PROB_FAILED_POST_START (43)`
- Meaning in this context: device is configured but miniport does not reach stable started/display state.
- Practical target: verify if failure is from early KMD init, missing caps path, or start sequencing.

1. `STATUS_GRAPHICS_*` traces including prior `0xC01E0438` observations
- Treat as graphics start-path mismatch/capability negotiation fault.
- Practical target: force minimal-safe adapter behavior first, then re-enable features progressively.

## Phase A strategy (next batch)
1. Keep no-reboot safety and signed package gate as hard requirements.
1. Run only small, isolated deltas per iteration (one change vector at a time).
1. Prioritize start-path toggles before deeper code changes:
- Service start mode
- Bind/restart order
- Root display cleanup
- Optional AMD helper service state
1. Capture midpoint and timeout state every iteration to avoid idle/stall.
1. Auto-recover to baseline after each failed activation.

## New batch definition
- Script: `tools/bc250-phaseA-batch.ps1`
- Properties:
  - Unique iteration IDs with timestamp
  - Midpoint check
  - Hard timeout
  - Automatic retry/recovery
  - CSV + JSON summary output
  - Writes tested combination key to avoid accidental duplicate combinations inside a run

## Planned test vectors in this batch
- `svc_demand`
- `svc_auto`
- `bind_then_restart`
- `disable_enable_cycle`
- `root_display_cleanup`
- `rescan_first`

## Success criteria for promoting a variant
1. Activation does not end in black-screen lock.
1. Post-activation state is not stuck on immediate Code 43.
1. Variant repeats at least 3 times with same non-regressive behavior.
1. If stable, save as known-good iteration snapshot before further tuning.

## Immediate next action
Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-phaseA-batch.ps1 -Iterations 24
```

