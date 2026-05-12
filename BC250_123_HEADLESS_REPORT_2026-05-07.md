# BC-250 Headless Run Report (Steps 1, 2, 3)

Date: 2026-05-07
Target: `192.168.50.189`
Mode: Headless, signed driver package, guarded install, automatic baseline rollback, reboot between iterations.

## Scope Executed

1. **UMA consistency lock** in `QueryAdapterInfo` for `DRIVERCAPS` + `QUERYSEGMENT`/`QUERYSEGMENT2`/`QUERYSEGMENT3`.
2. **First-failure instrumentation** in `StartDevice` and `QueryAdapterInfo` (stage/status map + query trace counters).
3. **Memory-only iteration batch**: only `AMDBC250_REPORTED_VRAM_MB_OVERRIDE` changed per run.

## Code Changes

- `E:\world view\BC250-windowsDriverTest\amdbc250_kmd.c`
  - Added `AMDBC250_REPORTED_VRAM_MB_OVERRIDE` and shared UMA segment-flag macro.
  - Added `Bc250CaptureFirstFailure(...)` and `Bc250TraceQueryResult(...)`.
  - Added `DebugFirstFail*` and `DebugQuery*` reporting in StartDevice logs.
  - Switched `QueryAdapterInfo` returns to a trace wrapper (`BC250_QAI_RETURN`) for status mapping.
  - Unified paging-buffer constant for `QUERYSEGMENT3`.
- `E:\world view\BC250-windowsDriverTest\amdbc250_kmd.h`
  - Added debug fields:
    - `DebugFirstFailStage`, `DebugFirstFailStatus`
    - `DebugQueryCount`, `DebugQueryLastType`, `DebugQueryLastOutSize`, `DebugQueryLastStatus`, `DebugQueryLastVramBytes`
- Mirrors synced:
  - `E:\world view\BC250-windowsDriverTest\zip\amd-bc250-driver\src\kmd\amdbc250_kmd.c`
  - `E:\world view\BC250-windowsDriverTest\zip\amd-bc250-driver\inc\amdbc250_kmd.h`
- Test harness updates:
  - `E:\world view\bc250_single_iter_remote.ps1`: added `-ReportedVramMb` and logging.
  - `E:\world view\bc250_memoverride_reboot_batch_local.ps1`: new memory-only reboot batch with half-time check.

## Test Evidence

Primary log pulled from target:
- Remote: `C:\Dev\BC250-windowsDriverTest\tools\reboot_iter_batch.log`
- Local copy: `E:\world view\reboot_iter_batch_20260507_after123.log`

Batch runner log:
- `E:\world view\bc250_memoverride_batch_20260507_100652.log`

## Iteration Results (Timestamped)

| Iteration | Start | End | Variant | Event Result |
|---|---|---|---|---|
| RB1_h1_s1 | 09:38:14 | 09:39:06 | headless=1, skipHw=1 | Problem Status `0xC00000E5` |
| RB2_h1_s0 | 09:40:59 | 09:41:53 | headless=1, skipHw=0 | Problem Status `0xC00000E5` |
| RB3_h0_s1 | 09:43:42 | 09:44:35 | headless=0, skipHw=1 | Problem `0x15`, Status `0x0` |
| RB4_h0_s0 | 09:46:25 | 09:47:17 | headless=0, skipHw=0 | Problem Status `0xC00000E5` |
| M01_1024MB | 10:09:23 | 10:10:17 | reportedVramMb=1024 | Problem Status `0xC00000E5` |
| M02_2048MB | 10:12:46 | 10:13:39 | reportedVramMb=2048 | Problem Status `0xC00000E5` |
| M03_4096MB | 10:16:06 | 10:16:59 | reportedVramMb=4096 | Problem `0x15`, Status `0x0` |
| M04_8192MB | 10:19:27 | 10:20:20 | reportedVramMb=8192 | Problem Status `0xC00000E5` |

All iterations ended with forced baseline recovery to `display.inf` / `BasicDisplay` (`CM_PROB_NONE`) before next reboot.

## Observations

- Changing reported VRAM size alone did **not** remove the dominant failure signature (`Problem Status 0xC00000E5`).
- `4096MB` is the only memory-only point in this run that shifted to `Problem 0x15 / Status 0x0`.
- Driver package signing/build/install loop stayed stable in headless mode; no stuck iteration in this batch.

## Next Recommended Batch (not yet run in this report)

- Keep `ReportedVramMb=4096` fixed.
- Vary one field per iteration among:
  - `QUERYSEGMENT3.PagingBufferSize` (`64KB`, `128KB`, `256KB`)
  - `DRIVERCAPS.WDDMVersion` mapping (`1.3` vs `2.0` capability report only)
  - `SegmentCount strategy` (`QUERYSEGMENTCOUNT=1` vs explicit mirror to QSEG3 path)
- Continue reboot-between-iterations and baseline verification after each run.
