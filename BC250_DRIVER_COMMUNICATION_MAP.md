# BC-250 Windows Driver Communication Map

Updated: 2026-05-02 (Europe/Stockholm)

## Scope
This document maps how the BC-250 display stack communicates during driver bind/start, based on verified headless test runs and Windows event logs.

## Hardware/Platform Context
- Device: `PCI\VEN_1002&DEV_13FE&SUBSYS_00001022`
- Platform: BC-250 (Family 23 Model 71), UMA memory architecture
- Working baseline display path: `display.inf` (`BasicDisplay`)
- Competing vendor path: AMD package (`oem9.inf`, `amduw23g`)
- Custom path under test: `oem23.inf` (`amdbc250kmd`)

## High-Level Communication Flow
1. PnP ranking selects driver package for the PCI instance.
2. Service object is created from INF `AddService`.
3. SCM attempts kernel-driver load (`\SystemRoot\System32\drivers\*.sys`).
4. If load succeeds, Dxgkrnl starts miniport lifecycle:
   - `DxgkDdiAddDevice`
   - `DxgkDdiStartDevice`
   - `DxgkDdiQueryAdapterInfo` (multiple `DXGKQAITYPE_*`)
5. If any stage fails, Kernel-PnP emits Event 411 and the device lands in problem state.
6. Recovery path rebinds `display.inf` to restore output.

## What Works vs Fails
### Works
- INF install/signing pipeline (test-signing): package accepted.
- Service registration from INF: present in SCM events.
- Fallback/recovery path: reliably returns to `display.inf` (`CODE=0`).

### Fails
- Custom miniport start path on BC-250:
  - Kernel-PnP Event 411 repeatedly shows start failure on `oem23.inf`.
  - Additional Event 219 observed: `\Driver\amdbc250kmd failed to load`.

## Observed Error Signatures
### Signature A (older batches)
- Event 411:
  - `Problem: 0x25`
  - `Problem Status: 0xC0000059`
- Interpretation: start failure from kernel path during/after bind (service present, start rejected/fails).

### Signature B (variant batch)
- Event 411:
  - `Problem: 0x0`
  - `Problem Status: 0xC00000E5`
- Interpretation: internal error returned in start path (no specific CM problem code attached).

### Signature C (vendor AMD package)
- Device often reaches:
  - `CODE=43` (`CM_PROB_FAILED_POST_START`) under `amduw23g`
- Interpretation: binds, attempts runtime init, fails post-start and rolls back.

## Key Comparative Behavior
- Original AMD driver path shows dynamic memory activity in GPU-Z before failure transitions.
- Custom driver path shows no dynamic memory telemetry when activated.
- This strongly suggests custom path fails before successful UMA memory bring-up/telemetry exposure.

## Internal KMD Areas Touched During Testing
- `DxgkDdiQueryAdapterInfo`:
  - `DRIVERCAPS`
  - `QUERYSEGMENT`, `QUERYSEGMENT2`, `QUERYSEGMENT3`, `QUERYSEGMENTCOUNT`
  - `WDDMDEVICECAPS`
- `DxgkDdiStartDevice`:
  - full init path and compatibility fallback path
  - headless on/off
  - skip-hardware-init on/off

## Variant Matrix Already Tested (No Need to Repeat)
### INF/section path sweeps
- Rembrandt/Mendocino/Phoenix/Raphael/DragonRange/Navi*/Legacy
- `SoftwareDeviceSettings` variants
- Result: all still fail start/post-start (no stable success)

### KMD toggle matrix
- `HEADLESS_RENDER_ONLY` in `{0,1}`
- `SKIP_HW_INIT` in `{0,1}`
- WDDM handshake lowered (1.3, 1.2)
- Result: no stable start; shifted between Signature A/B but not fixed.

## Most Important Current Finding
A direct load failure was captured:
- Kernel-PnP/System event includes: `\Driver\amdbc250kmd failed to load`
- This narrows root cause to loader/start-chain constraints, not just high-level caps/INF mapping.

## Communication Bottleneck Hypothesis
Primary bottleneck likely occurs before meaningful runtime memory negotiation:
- either loader-level acceptance/runtime dependency mismatch,
- or earliest miniport start contract mismatch causing immediate load/start abort.

## Recommended Next Investigation Order
1. Loader-level failure reason extraction (highest priority)
   - correlate Event 219 + Event 411 + setupapi sections at same timestamps.
   - verify binary dependencies/import surface and entry contract for target WDDM level.
2. Strict minimal DDI surface experiment
   - reduce callback surface in `DriverEntry` to proven-safe subset and retest start.
3. Incremental re-enable
   - add callbacks/caps back in small groups while monitoring Event 411 status transitions.
4. UMA memory path re-entry
   - only after stable load/start, continue fine-grained memory init tuning.

## Operational Safety Pattern (Retain)
Per iteration:
- build -> sign -> guarded bind -> 20-35s observe -> auto fallback
- if not started: force `display.inf` recovery immediately
- avoid reboot unless explicitly needed

## Artifacts/Logs to Use
- `C:\Dev\BC250-windowsDriverTest\guarded-test.log`
- `C:\Dev\BC250-windowsDriverTest\tools\headless_variant_batch.log`
- `C:\Dev\BC250-windowsDriverTest\tools\headless_variant_batch2.log`
- Kernel-PnP/Configuration Event IDs: `400`, `410`, `411`
- System Event IDs seen during bind: `219`, `7045`

## Decision Guidance
Do not spend more cycles on broad INF map permutations now.
Focus next on kernel load/start contract isolation, because that is where the strongest hard-fail evidence exists.

## Live Update (2026-05-02 15:00)

### Current Device State
- Active fallback driver: `display.inf` (`BasicDisplay`), status `Started`.
- Custom package present but outranked: `oem23.inf` (`amdbc250.inf`).
- Service object exists: `amdbc250kmd` (demand-start, stopped).

### Critical New Evidence
From **System** and **SetupAPI** logs during custom bind attempts:

1. **SCM Event 7000**:
- `The AMD BC-250 Kernel Display Miniport service failed to start`
- Error text: **`Indicates two revision levels are incompatible.`**

2. **Kernel-PnP Event 219**:
- `\Driver\amdbc250kmd failed to load` for `PCI\VEN_1002&DEV_13FE...`

3. **SetupAPI.dev.log** (authoritative line):
- `CM_PROB_FAILED_DRIVER_ENTRY`
- `problem status: 0xC0000059`

This confirms the failure is at **driver entry/load contract level**, not only post-start memory init.

### Impact on Debug Strategy
Stop broad memory/UMA tuning as primary path for now.
Prioritize strict compatibility of miniport contract with target stack:
- interface/version handshake,
- required callback contract for declared interface level,
- binary/service entry expectations.

### Updated Priority
1. Reproduce with minimal callback surface + lowest stable interface declaration.
2. Validate DriverEntry/StartDevice contract expectations against the active WDDM stack.
3. Re-introduce memory/segment sophistication only after load/start contract is stable.
