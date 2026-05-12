# BC-250 Driver Research Handoff (Comprehensive)

## Scope
This document summarizes all major BC-250 Windows driver experiments, observed faults, reasoning behind each experiment, and current actionable direction. It is intended for a planning/research bot to design the next high-value test strategy.

## Environment
- Target host: `192.168.50.200` (BC-250)
- Device under test: `PCI\VEN_1002&DEV_13FE&SUBSYS_00001022`
- Main recovery baseline: `display.inf` + `BasicDisplay`
- Main runtime fault signatures:
  - `CM_PROB_FAILED_POST_START` (Code 43)
  - `CM_PROB_FAILED_ADD` (intermittent `ROOT\DISPLAY\0000`)
  - `0xC01E0438` (`STATUS_GRAPHICS_NOT_POST_DEVICE_DRIVER`)

## High-Level Outcome So Far
1. **Operational progress:** headless testing and rollback became reliable and fast.
2. **Functional progress:** no sustained driver activation success yet.
3. **Strongly established:** INF selection/signing issues were real early blockers, but even after signed best-ranked Radeon bind, runtime still fails post-start with Code 43.
4. **Current state:** we can iterate quickly with safety, but root cause remains in display miniport/runtime startup path.

## Test Program Structure
Two main paths were used:
- **Path A (Radeon INF path):** patch official AMD package to include BC-250 IDs, sign catalog, bind, observe.
- **Path B (Custom KMD/UMD path):** evolve `amdbc250` code and WDDM contracts, package/sign/install, observe.

Safety/recovery harnesses used:
- Guarded no-reboot loops with automatic rollback.
- Signed-only gate enforcement for each package.
- Auto-recovery scripts to return to `display.inf` baseline.

## Key Fault Patterns by Category

### A) Signature / Ranking / Selection
- Early runs proved that unsigned or improperly signed INF changes cause rank/signer issues and misleading outcomes.
- Later runs proved a **fresh signed Radeon package** can be best-ranked and selected for BC-250.
- Despite this, runtime still fails (`Code 43`) -> selection is no longer the main blocker.

### B) Service / Helper Policy
- `amduw23g` service start-type and helper services (`AMD External Events`, `Crash Defender`) were perturbed.
- Forcing demand, forcing auto, pre-starting service: no functional change.
- Bind flow can overwrite service policy during install/start sequence.

### C) INF Section Mapping Sweeps
- Broad section mapping sweeps across Navi/APU/RDNA families were executed with signed packages.
- Repeated invariant result: `CM_PROB_FAILED_POST_START` with `amduw23g` after bind.
- Conclusion: section remap alone is low-yield/exhausted.

### D) Custom KMD Startup Contracts (Path B)
- WDDM version preference changes, QueryAdapterInfo expansions, VidPN-related adjustments, UMD registration consistency, service-start diagnostics, and no-hardware fallback paths were tested.
- KMD image can be loaded/signed; setup/config can succeed, but device still falls into post-start failure.
- No single contract tweak has moved outcome to a stable started adapter.

### E) Baseline Drift / Recovery
- Occasionally, after failed runs, baseline itself drifts to `display.inf + Code 43`.
- A no-reboot recovery playbook was developed (remove phantom display node, remove stale packages, rescan, re-enumerate/rebind).
- Recovery often works, but some recent instrumented runs produced a harder stuck state that required repeated recovery attempts.

## Condensed Timeline of Major Test Waves

### Wave 1: Path B startup semantics hardening (T-001..T-032)
- Tested caps, DDI table permutations, render/display posture, UMD registration, service start style, restart/disable-enable cycles, explicit service start, query segment fixes, WDDM 2.0 preference.
- Net: no successful activation; reliable evidence that package/sign/install can succeed while post-start still fails.

### Wave 2: Path A signed Radeon bind and mapping exhaust (T-033..T-040)
- Fresh signed Radeon package created and selected as best-ranked for BC-250.
- Repeated map sweeps (`Navi10/14/21/22/23/24/31/32/33`, `Mendocino`, `Phoenix`, `Raphael`, `DragonRange`, `Legacy`, `Rembrandt`) all failed identically with Code 43.
- Helper service perturbations did not change outcome.

### Wave 3: Fast safe iterations and stability characterization (T-041..T-045+)
- Added auto-recovery wrapper and high-speed short-window loops.
- Many iterations now complete without transport loss and often without visible long blackout.
- Runtime fault unchanged: still Code 43 on activation, then rollback to baseline.

## Specific Files and Components Most Relevant to Failure

### Custom driver files (Path B)
- `amdbc250_kmd.c`
  - `DriverEntry`, `Bc250DdiAddDevice`, `Bc250DdiStartDevice`, `Bc250DdiQueryAdapterInfo`
- `amdbc250_hw_init.c`
  - `Bc250HwInitialize` and SMU/memory/ring/display init steps
- `amdbc250_kmd.h`
  - device extension and diagnostics fields
- `amdbc250.inf`
  - service and UMD registry wiring

### Radeon path files (Path A)
- `u0397406.inf` and cloned variants in `WT6A_INF`
- catalog/signature artifacts generated via `Inf2Cat` + `signtool`

## Latest Deep-Debug Instrumentation Added
To isolate exact startup failure stage in custom KMD path:
- Added `DebugStartStage`, `DebugStartStatus`, `DebugHwInitStage`, `DebugHwInitStatus` in device extension.
- Added breadcrumb stage constants and logging in `Bc250DdiStartDevice`.
- Added breadcrumb stage constants and logging in `Bc250HwInitialize`.
- Changed SMU init timeout behavior to return real failure status (no silent success masking).

Latest instrumented guarded run result:
- Build/sign/install succeeded.
- Adapter still ended in post-start failure and fallback.
- Baseline then became harder-stuck at `display.inf + Code 43`.
- Existing no-reboot recovery did not always clear this immediately.

## Hypotheses Status Matrix

### Ruled Out / Low Probability
- "Just add PCI ID to INF" as a complete fix.
- Helper AMD service start-type as primary cause.
- Single section map choice as primary cause.
- Signature alone (after successful signed best-ranked bind) as sole blocker.

### Still Plausible / Active
- Core runtime initialization incompatibility in AMD display miniport path on BC-250 (firmware/init/post ownership expectations).
- Missing/incorrect startup contracts in custom KMD beyond current implemented subset.
- Device-state transition/post-driver-state interaction causing persistent Code 43 after failed attempts.
- Need for deeper kernel-level logging (DbgPrint/ETW/kernel debug) to identify first failing callback/stage conclusively.

## Fault Codes and Interpretation
- `CM_PROB_FAILED_POST_START (43)`: device reported problems after start path.
- `CM_PROB_FAILED_ADD (31)`: seen on phantom/root display node in some bind attempts.
- `0xC01E0438 STATUS_GRAPHICS_NOT_POST_DEVICE_DRIVER`: indicates display stack rejects attempted active path in this workflow context.

## What Worked Operationally
- Signed-only strict gate per test.
- Fast no-reboot loops with auto rollback.
- `bc250-safe-iterate.ps1` wrapper for baseline pre/post checks.
- Timestamped evidence capture for each iteration.

## What Did Not Produce Functional Gain
- Large-scale Radeon section cycling.
- AMD helper-service policy perturbations.
- Multiple one-off WDDM contract toggles without deep stage telemetry correlation.

## Recommended Next-Step Plan Inputs for Research Bot
The planner should prioritize:
1. **Deep observability first:** capture kernel debug output for stage breadcrumbs and first failing status.
2. **Single-variable experiments only:** no broad map sweeps unless new evidence suggests relevance.
3. **Split strategies:**
   - Path A runtime diagnostics (not mapping churn)
   - Path B StartDevice/HW init contract validation with stage-status verification
4. **Recovery robustness:** improve baseline recovery for stuck `display.inf + Code 43` before aggressive runs.
5. **Stop condition per run:** if iteration exceeds ~3 minutes or recovery fails, mark run invalid and recover immediately.

## References in This Workspace
- Detailed matrix: `E:\world view\BC250-windowsDriverTest\TEST_MATRIX.md`
- Knowledge base: `E:\world view\BC250-windowsDriverTest\BC250_DRIVER_KNOWLEDGE_BASE.md`
- Safe loop script: `E:\world view\BC250-windowsDriverTest\tools\bc250-safe-iterate.ps1`
- Runtime telemetry script: `E:\world view\BC250-windowsDriverTest\tools\bc250-runtime-telemetry.ps1`

## Last Known Practical State
- Testing can continue headless with guarded rollback loops.
- Functional success criterion (stable non-basic AMD driver started without Code 43) is still unmet.
