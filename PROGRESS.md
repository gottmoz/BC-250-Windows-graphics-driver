# BC-250 Parallel Sprint Progress

## 2026-04-29

- Coordinator: created shared safety pipeline scripts:
  - `shared/deploy.ps1`
  - `shared/recover.ps1`
  - `shared/vm-test.ps1`
  - `shared/pathA-prepare-adrenalin-inf.ps1`
- Added guarded baseline recognition in remote harness so `display.inf + CM_PROB_FAILED_ADD + 0xC01E0438` is treated as expected safe non-POST baseline.
- Latest fast live-only cycle: driver bound (`CM_PROB_NONE`) and restored safe state in ~35s.
- Known-good snapshot saved remotely:
  - `C:\Dev\BC250-windowsDriverTest\known-good\stable-20260429-094654-headless-umdprivate-started`

## Current blocker

- BC250 miniport can PnP-start, but D3DKMT/DXGI still enumerate only Microsoft software adapters.
- Next focus: adapter publication path (KMD<->UMD handshake / caps / runtime enumeration), no risky boot-start testing.
- Current transport issue: SSH to `192.168.50.200` is timing out; next live iteration is queued once connectivity is restored.

### 2026-04-29 17:59 CEST
T-021 built and installed but did not load the kernel service. The runner now forces a post-bind no-reboot `pnputil /restart-device` to make each iteration exercise `DriverEntry`/`DxgkDdiStartDevice` before fallback.

### 2026-04-29 18:01 CEST
T-022 showed `pnputil /restart-device` is not enough to produce useful miniport load diagnostics. Next loop will use explicit devcon restart and stronger pre-fallback capture.

### 2026-04-29 18:02 CEST
T-023 added devcon instance restart but still did not produce miniport load evidence. T-024 will force no-reboot disable/enable after binding.

### 2026-04-29 18:04 CEST
T-024 disable/enable still did not load the miniport. T-025 will explicitly `sc start` the bound unique kernel service to distinguish image-load failure from PnP/display-stack replacement behavior.

### 2026-04-29 18:05 CEST
T-025 proved the KMD image loads with `sc start` but the PCI display adapter remains Code 43. This separates image/signature issues from PnP/Dxgk binding/display-stack replacement issues.

### 2026-04-29 18:06 CEST
T-025 pulled log confirms service RUNNING after explicit `sc start`. T-026 will restart the PCI device after service load to test whether PnP binds once the driver object exists.

### 2026-04-29 18:16 CEST
T-027 completed build-only cleanup. Added `bc250-driver` skill to local Codex skills, removed compatibility-start unreachable KMD code from the build, fixed PM4 header signedness, mirrored/deployed source to target, and verified KMD/UMD build with explicit remote MSBuild. No runtime bind/reboot was performed; target remains on safe BasicDisplay baseline.

### 2026-04-30 00:32 CEST
Reviewed Keshas-dev/AMD-bc-250-win. It is reference-only: one commit, only README.md, no source/INF/build artifacts. Useful claims match existing notes: BC-250/Cyan Skillfish as PS5 Oberon variant, PCI IDs 13FE/143F/13DB/13F9/13FA/13FB/13FC, DCN 2.01, UMA 16GB GDDR6, missing CP microcode load (`navi10_pfp.bin`, `navi10_me.bin`, `navi10_mec.bin`), UMD limited to D3D9 concept only. No code to merge. Keep as background source only.

### 2026-04-30 00:33 CEST
Reviewed PS5 DevWiki for BC-250 relevance. Useful pages: GPU, Hardware, Memory, PUP, Build Strings, Devices. Findings: PS5 GPU is RDNA2 up to 2.23GHz / 10.28 TFLOPS; memory is 16GB GDDR6 on a 256-bit bus; PUP outer format is `SLB2` with file table at `0x30`; update order includes oberon_sec_ldr_c0.bin, kernel.bin, ssd0.system_b, ssd0.system_ex_b; VBIOS build strings show AMD ATOMBIOS AMDObrGeneri; Devices page lists /dev/gc as GPU command, /dev/dbggc_control as debug GPU, /dev/mp1 SMU with clock IOCTLs, and /dev/pup_update0 decrypt/verify segment IOCTLs. Driver implication: PS5 PUP cannot provide useful GPU blobs without decrypted payloads; focus remains Linux amdgpu/firmware and Windows WDDM KMD PnP/VidPN stability.

### 2026-04-30 00:49 CEST
Analyzed decrypted PS5UPDATE1.PUP.dec. Added `tools/parse_ps5_decrypted_pup.py`, a Python unpacker for decrypted PS5 PUP fragments with blocked zlib segment support. Extracted small/core segments, ssd0.system_b, and ssd0.system_ex_b; parsed both large exFAT images. Found PS5 graphics userland paths (libSceAgc*, libSceGnmDriver*, libSceVideoOut*, AgcCompositor.elf, gpudump.elf, libSceGLSlim*), but they remain SELF/SPRX high-entropy containers, not plain code. No usable AMD CP/PFP/ME/MEC/SMU/DCN firmware or register tables found. Driver strategy unchanged: continue KMD PnP/VidPN stability and Linux amdgpu/AMD firmware research for CP microcode.

### 2026-04-30 00:59 CEST
Ran two fast headless iterations with fresh target evidence:
1) WDDM2.0 registration preference in DriverEntry.
2) DXGKQAITYPE_QUERYSEGMENT2/3 support in DxgkDdiQueryAdapterInfo.
Both built and deployed cleanly, both failed runtime start the same way (Device Status 0x01802400, fallback to BasicDisplay Code 43). This narrows the issue away from package signing/ranking and away from basic segment-query support.

### 2026-04-30 01:12 CEST
T-030 completed successfully as a fast iteration (45.7s) after fixing remote build PDB contention in shared/remote-iter-fast.ps1. Build and signing are stable again. Runtime remains Code 43 with fallback to BasicDisplay. New actionable defect identified in package generation: InstalledDisplayDrivers still writes a non-unique base (mdbc250umd) while UserModeDriverName is unique. Next patch aligns those registry values to remove UMD name mismatch during display miniport bind/start.

### 2026-04-30 08:20 CEST
Executed two back-to-back headless iterations. T-031 failed at compile due to one kernel constant and was fixed immediately. T-032 completed in 43.7s with the instrumentation patch active; behavior remained unchanged (Code 43 fallback). This confirms the current blocker is deeper in Dxgk display-start contract/publication, not package/sign/load plumbing.

### 2026-05-03 11:43 CEST
Ran init_contract_batch.ps1 (6 no-reboot iterations, ~43-44s each) targeting DRIVER_INITIALIZATION_DATA contract permutations (Version = WDDM1.3/WDDM2.0/SDK default, QueryInterface/QueryAdapterInfo on-off, Interrupt/DPC on-off) while keeping KMDOD-min callbacks.
Result: all variants failed identically with CM_PROB_FAILED_DRIVER_ENTRY and SetupAPI problem status: 0xC0000059 (STATUS_REVISION_MISMATCH). No differentiating signal observed. Auto-fallback restored display.inf safe baseline after each run.

### 2026-05-03 13:26 CEST
Executed init_api_ab_batch.ps1 (4 no-reboot iterations, halftime checks enabled) with variants:
- AB1_dxgk_baseline
- AB2_dxgk_sdkver (DriverInitData.Version = DXGKDDI_INTERFACE_VERSION)
- AB3_dod_vsync_on (DxgkInitializeDisplayOnlyDriver / KMDDOD)
- AB4_dod_vsync_off (KMDDOD without VSync callback group)
All variants failed identically with CM_PROB_FAILED_DRIVER_ENTRY, SetupAPI problem status: 0xC0000059.
Then ran filter/stack probe: no class or device UpperFilters/LowerFilters on BC-250 display node, so filter-driver interference is unlikely root cause.
### 2026-05-03 13:44 CEST
Ran `tools/init_version_matrix_batch.ps1` on BC-250 (8 no-reboot, signed iterations; halftime check at 60s each):
- VM1 WDDM1.3
- VM2 WDDM2.0
- VM3 WDDM2.1
- VM4 WDDM2.2
- VM5 WDDM2.3
- VM6 WIN8
- VM7 literal 0x4002
- VM8 literal 0x5023
All eight variants failed identically with `CM_PROB_FAILED_DRIVER_ENTRY` and SetupAPI problem status `0xC0000059`.
This de-risks pure `DriverInitData.Version` selection as primary root cause.
Safe fallback validated immediately after batch (`display.inf` / `BasicDisplay`, ProblemCode 0).
Also extracted WDK constants from target `d3dukmdt.h`: `DXGKDDI_INTERFACE_VERSION_WDDM1_3=0x4002`, `WDDM2_0=0x5023`, `WDDM2_1=0x6003`, `WDDM2_2=0x700A`, `WDDM2_3=0x8001`, `WDDM2_4=0x9006`, `WDDM2_5=0xA00B`, `WDDM2_6=0xB004`, `WDDM2_7=0xC004`.
### 2026-05-03 13:53 CEST
Ran `tools/compile_dxgkver_batch.ps1` on BC-250 to test compile-time `DXGKDDI_INTERFACE_VERSION` contract changes (not just runtime `DriverInitData.Version`):
- default compiler macro
- forced WDDM1.3
- forced WDDM2.0
- forced WDDM2.1
- forced WIN8
All 5 signed no-reboot iterations still failed identically with `CM_PROB_FAILED_DRIVER_ENTRY` and SetupAPI problem status `0xC0000059`.
Conclusion: failure is not explained by runtime-only or compile-time-only DXGK interface version selection.
Safe baseline restored after batch (`display.inf` / `BasicDisplay`, ProblemCode 0).
### 2026-05-03 13:59 CEST
Re-ran DriverEntry gate batch (baseline + forced `STATUS_SUCCESS` + forced `STATUS_NOT_SUPPORTED`).
Observed no change in outward failure signature: still `CM_PROB_FAILED_DRIVER_ENTRY` with SetupAPI problem status `0xC0000059`.
Added event-level decode from Kernel-PnP ID 219: `EventData.Status=0xC0000365` (`STATUS_FAILED_DRIVER_ENTRY`) for each generated `amdbc250kmdt*` service instance.
This confirms the load/start path is failing at driver-entry stage from the PnP perspective, while SetupAPI simultaneously records revision mismatch context.
### 2026-05-07 10:20 CEST
Executed headless Step 1/2/3 batch on `192.168.50.189` with signed package + reboot-between-iterations safety.

Implemented:
- UMA reporting consistency and single-source segment flags in `QueryAdapterInfo`.
- First-failure telemetry map (`DebugFirstFail*`) and query telemetry (`DebugQuery*`) in KMD.
- Memory-only iteration runner (`AMDBC250_REPORTED_VRAM_MB_OVERRIDE`) with half-time checks.

Runs completed:
- RB1..RB4 (headless/skipHw matrix)
- M01..M04 (reportedVramMb 1024/2048/4096/8192)

Outcome:
- Dominant failure remains Kernel-PnP Problem Status `0xC00000E5`.
- Alternate signature appears at 4096MB (`Problem 0x15`, `Status 0x0`).
- Every run recovered back to `display.inf`/`BasicDisplay` (`CM_PROB_NONE`) before next reboot.

Evidence files:
- `E:\world view\reboot_iter_batch_20260507_after123.log`
- `E:\world view\bc250_memoverride_batch_20260507_100652.log`
- `E:\world view\BC250-windowsDriverTest\BC250_123_HEADLESS_REPORT_2026-05-07.md`
### 2026-05-07 11:23 CEST
Started autonomous headless new-track batch (duration 6h) on local orchestrator process `PID 25096`:
- Script: `E:\world view\bc250_headless_newtracks_autoloop.ps1`
- Runtime log (stdout mirror): `E:\world view\autoloop_bg.out.log`
- Runtime error log: `E:\world view\autoloop_bg.err.log`
- Detailed batch log: `E:\world view\bc250_headless_newtracks_20260507_112005.log`

Track set (cycling with reboot + baseline check each iteration):
- Paging buffer: 64KB / 128KB / 256KB
- WDDM caps level: auto / 1.3 / 2.0
- UMA flags profile: default / cache-coherent / aperture-profile
- Fixed baseline for track isolation: headless=1, skipHw=1, reportedVramMb=4096
### 2026-05-07 21:25 CEST
Error investigation completed:
- Decoded `0xC00000E5` as `STATUS_INTERNAL_ERROR` (ntstatus.h).
- Decoded `Problem 0x15` as `CM_PROB_WILL_BE_REMOVED` (cfg.h).
- Isolated `NT05` batch build failure root cause: forced WDDM2.0 path referenced undefined `DXGKDDI_WDDMv2_0` in 19041 KM headers.

Applied fix:
- Guarded forced `WddmCapsLevel=20` return path with `#if defined(DXGKDDI_WDDMv2_0)` fallback to WDDM1.3.

Validation:
- Remote compile probe now succeeds (`W20_BUILD_EXIT=0`).
- Runtime retest `NT05_retest_after_fix` now executes full install/test path (no build fail), event signature currently `Problem 0x0 / Status 0xC00000E5`.
### 2026-05-07 21:52 CEST
Executed forensic DriverEntry contract sequence on 192.168.50.189 with one-change-per-run discipline:
1) A1 telemetry baseline,
2) A2 Version=DXGKDDI_INTERFACE_VERSION (fallback branches still in source),
3) A3 strict Microsoft DriverEntry form (RtlZeroMemory, direct DXGKDDI interface version, exact DxgkInitialize return).

Observed signal change:
- A1/A2 still correlated with explicit CM_PROB_FAILED_DRIVER_ENTRY /  xC0000059 in SetupAPI windows and SCM revision-incompatible messages.
- A3 produced event-411 signature Problem 0x15 / Status 0x0 without fresh  xC0000059 or SCM 7000 in the immediate forensic window, while preserving safe fallback to BasicDisplay.

This is the first clean run in tonight's sequence where the explicit revision-mismatch signature was not re-observed immediately after the iteration.
### 2026-05-07 21:56 CEST
Ran follow-up forensic contract test A4 (FORENSIC_A4_MINCALLBACKS) after A3 by reducing DriverEntry callback surface to a strict minimal set while keeping Version = DXGKDDI_INTERFACE_VERSION.
Observed same visible failure signature (Problem 0x15 / Status 0x0) but, in the immediate forensic window, no explicit FAILED_DRIVER_ENTRY/ xC0000059 or SCM revision-mismatch event reappeared.
This strengthens the hypothesis that the previous revision-mismatch class was tied to DriverEntry init-contract/callback registration rather than signing/INF selection.
### 2026-05-07 22:00 CEST
Snabbtest A5 kört med exakt minimal DriverEntry-tabell enligt användarinstruktion. Iterationen signerades och kördes headless utan extra variabler.
Utfall: tydlig Problem 0x15 / Status 0x0 kvarstår, men ingen ny explicit  xC0000059 i det direkta forensikfönstret.
### 2026-05-07 22:26 CEST
Executed forensic ladder continuation on target `192.168.50.189` with one-change-per-run discipline and signed guarded loop:
- A8 (`SetVidPnSourceAddress/Visibility + GetScanLine`) => `oem5.inf` Problem `0x0`, Status `0xC00000E5`.
- A9 (`ControlInterrupt` only; ISR/DPC still NULL) => `oem5.inf` Problem `0x15`, Status `0x0`.
- A10 (`Create/DestroyDevice` + allocation Open/Close/Create/Destroy only) => `oem5.inf` Problem `0x0`, Status `0xC00000E5`.

Baseline recovery succeeded after every run (`display.inf`/`BasicDisplay`/`CM_PROB_NONE`).
System logs in the bind window still show SCM 7000: "Indicates two revision levels are incompatible" for `amdbc250kmd`.

Artifacts:
- `E:\world view\BC250-windowsDriverTest\forensic_a8_extract_20260507.txt`
- `C:\Dev\BC250-windowsDriverTest\tools\reboot_iter_batch.log` (remote source of all A6-A10 lines)
### 2026-05-07 22:30 CEST
Ran two extra isolations after A10:
- `FORENSIC_A10B_ALLOC_NOCTRL`: removing `DxgkDdiControlInterrupt` flipped outcome from `0xC00000E5` to `Problem 0x15 / Status 0x0`.
- `FORENSIC_A11_CTX_ONLY`: adding `CreateContext/DestroyContext` on top of allocation set flipped back to `Problem 0x0 / Status 0xC00000E5`.

This indicates failure class is highly sensitive to scheduler-path callback exposure, even when HW init is skipped.
### 2026-05-07 22:39 CEST
Executed requested reboot on `192.168.50.189`, confirmed SSH and baseline state, then ran immediate post-reboot iteration (`FORENSIC_A11_POSTREBOOT`).
Outcome remained `Problem 0x15 / Status 0x0` with clean fallback to `display.inf`.
### 2026-05-07 22:59 CEST
Completed validated A7 microstep rerun (`R2`) from strict A6 base with passive VidPN patching:
- `RecommendFunctionalVidPn` now returns `STATUS_SUCCESS`.
- `EnumVidPnCofuncModality` now passive/read-only (`STATUS_SUCCESS` only).
- DriverEntry now controlled by `AMDBC250_A7_MICROSTEP` and A10/A11 callbacks remain parked (`NULL`).

R2 ladder outcome:
- A7a..A7e stayed on `Problem 0x15 / Status 0x0`.
- A7f (`+UpdateActiveVidPnPresentPath`) flipped to `Problem 0x0 / Status 0xC00000E5`.
- A7g returned to `Problem 0x15 / Status 0x0`.

This points to post-init VidPN path-update contract sensitivity rather than Enum topology mutation in current passive mode.
### 2026-05-07 23:12 CEST
Executed A7f primary-track probes exactly as requested (allocation/context/render still parked):
1) A7f-1 control (`UpdateActiveVidPnPresentPath=NULL` via A7e profile),
2) A7f-2 callback registered but returns `STATUS_NOT_SUPPORTED`,
3) A7f-3 callback registered and returns guarded `STATUS_SUCCESS` with detailed path logging.

All three produced `Problem 0x15 / Status 0x0` and passed baseline recovery. Repro rerun of A7f-3 matched same result.
This means prior A7f `0xC00000E5` is not reproduced under the new passive VidPN + guarded updatepath implementation.

Code probes added in `amdbc250_kmd.c`:
- `AMDBC250_UPDATEPATH_PROBE_MODE`
- Defensive `Bc250DdiUpdateActiveVidPnPresentPath` validation and logging
- A7 microstep gating retained (`AMDBC250_A7_MICROSTEP`)
### 2026-05-07 23:34 CEST
Implemented StartDevice/QAI forensic instrumentation and executed B1/B2/B3 sequence plus reproductions.

Code-level additions:
- Global lifecycle counters independent of DevExt (`g_DeCalledDriverEntry`, `g_DeDxgkInitializeSuccess`, `g_DeAddDevice`, `g_DeStartDevice`, `g_DeQueryAdapterInfo`, `g_DeStopDevice`, `g_DeRemoveDevice`).
- Global QAI history ring (last 20 entries) with type/out/status + dump helper.
- Safe display-profile callback registration path (no allocation/context/render/scheduler DDIs).
- Configurable unknown-QAI behavior via `AMDBC250_QAI_UNKNOWN_NOTSUPPORTED`.
- Configurable QAI dump-on-stop/remove via `AMDBC250_DUMP_QAI_ON_STOPREMOVE`.

Run outcomes:
- B1: `0xC00000E5`
- B2: `0x15/0x0`
- B3: `0xC00000E5`
- B2 repro: `0x15/0x0`
- B3 repro: `0x15/0x0`

Interpretation right now: failure class still bifurcates between `0x15/0x0` and `0xC00000E5`; `unknown->NOT_SUPPORTED` correlates with cleaner `0x15/0x0` in repeated runs, while `0xE5` remains intermittently reproducible under same broad profile.
### 2026-05-07 23:41 CEST
Applied B2-safe hardening as default test platform:
- `HEADLESS_RENDER_ONLY=0`, `SKIP_HW_INIT=1`, `REPORTED_VRAM_MB_OVERRIDE=4096`
- `unknown QueryAdapterInfo => STATUS_NOT_SUPPORTED`
- safe display profile active, allocation/context/render/scheduler DDIs still parked
- added global lifecycle counters + QAI ring history + additional lifecycle dumps
- conservative DRIVERCAPS (`SupportKernelModeCommandBuffer=FALSE`, `NbAsymetricProcessingNodes=0`)

Validation run `C3_B2SAFE_CONSERV_DRIVERCAPS` landed on `0x15/0x0` with successful baseline restore.
### 2026-05-07 23:45 CEST
Executed requested C4/C5/C6 series on B2-safe platform:
- C4 (WDDM 1.3): `0x15/0x0`
- C5 (segment v1-only, QSEG2/3 disabled): `0xC00000E5`
- C6 (force QSEG3 paging size 0): `0x15/0x0`

New signal: disabling QUERYSEGMENT2/3 entirely (C5) appears to push runtime back into INTERNAL_ERROR path, while keeping QUERYSEGMENT3 but forcing zero paging still stayed in cleaner `0x15/0x0` class.
### 2026-05-08 08:51 CEST
Started D-series with segment-flag focus from C4/C6-safe base.
Implemented explicit D1/D2 mappings in `BC250_SET_UMA_SEGMENT_FLAGS` and executed D1+D2+repro.

Observed:
- D1 (Aperture=1, non-coherent) => `0xC00000E5`
- D2 (Aperture=1 + CacheCoherent=1 + PopulatedFromSystemMemory=1) => `0x15/0x0` (stable on repro)

This suggests aperture path without coherent/system-memory semantics may violate expected segment contract in this minimal profile.

### 2026-05-08 16:45 CEST
Executed requested reboot with the best Linux-aligned D2+8192 package active.

Result:
- Build/sign/package passed on BC-250.
- `pnputil` installed `oem5.inf` and required reboot.
- After reboot, SSH returned, but the driver failed earlier than the prior clean `0x15/0` class: `CM_PROB_FAILED_DRIVER_ENTRY`, `ProblemStatus=0xC0000059`, Kernel-PnP Event 219 (`\Driver\amdbc250kmd failed to load`).
- Rolled back to `display.inf`; Microsoft Basic Display is `Started` again.

Interpretation: active boot-load path reintroduced the DriverEntry/interface failure class. The next fix should focus on why the reboot bind differs from the no-reboot D2+8192 guarded runs, likely package/build variant or DriverEntry/DDI table drift, before more VidPN/segment tuning.

### 2026-05-08 17:11 CEST
Ran `K0_STRICT_DRIVERENTRY_REVALIDATE` with no reboot, per user constraint.

What was proven:
- The package pipeline now verifies the exact binary: marker present in `.sys`, SHA256 captured, fresh timestamp, signed SYS/CAT, CAT verify PASS.
- The actual K0 package used strict DriverEntry minset and true D2 flags (`8192MB`, `UMA_FLAGS_PROFILE=2`).
- No stale package was left active; rollback returned BC-250 to `display.inf` / Basic Display / Started.

Result:
- No-reboot install selected `oem2.inf` and returned `3010`.
- Device remained `CM_PROB_NEED_RESTART`; restart-device could not complete because Windows had a pending reboot operation.
- Event 219 still logged `\Driver\amdbc250kmd failed to load`, but without reboot this is not enough to separate DriverEntry ABI failure from pending-restart load semantics.

Next useful no-reboot step: avoid `/install` pending-reboot semantics and test service image load directly with a temporary service name/path or `sc start` immediately after staged package verification, while keeping BasicDisplay bound.

### 2026-05-08 19:53 CEST
Ran K1 no-reboot service-load gate with verified K0 marker/hash.

Signal:
- `sc start` on temporary kernel service failed with Win32 `1306` (`ERROR_REVISION_MISMATCH`).
- SCM Event 7000 confirms the same mismatch text.

This is strong evidence the current failure is not mainly in VidPN/QSEG runtime callbacks; it appears earlier in driver image/interface compatibility. Next work should focus on binary/headers/toolset contract and imports, with minimal DriverEntry surface retained.

### 2026-05-08 20:01 CEST
L1 proved the environment is healthy for signed no-reboot kernel service loads: `bc250hello.sys` starts and runs (`sc start` exit 0).

This narrows current blocker to BC250 KMD binary/interface contract itself (imports/PE/entry/DDI contract), not global signing or SCM behavior.

Next immediate focus: L2/L3 comparison against known-good minimal display sample and strict import/headers/toolset diff for `amdbc250kmd.sys`.

## 2026-05-08 20:13 L2_PROJECTSWAP_KMD_CONTEXT (no reboot)
- Method: temporary source swap in `amdbc250_kmd.c` inside real `amdbc250kmd.vcxproj`, rebuild/sign, unique temp kernel service start.
- L2b variant: `#include <dispmprt.h>`, minimal DriverEntry+Unload, no DxgkInitialize call.
- L2c variant: same + forced `DxgkInitialize` symbol reference.
- Result:
  - `BUILD_EXIT_l2b=0`, `SIGN_EXIT_l2b=0`, `SC_START_EXIT_l2b=1306`
  - `BUILD_EXIT_l2c=0`, `SIGN_EXIT_l2c=0`, `SC_START_EXIT_l2c=1306`
  - service state stopped, `WIN32_EXIT_CODE=1306` for both.
- Artifact log: `C:\Dev\BC250-windowsDriverTest\l2_projectswap_20260508_201358.log`
- Notes:
  - Both variants produced identical sys hash (`14F07A...17F92`) in this build context.
  - Confirms revision mismatch is tied to KMD project/link image contract, not runtime VidPN/QSEG path.

## 2026-05-08 20:29 L2F_SINGLE_OBJ_MANUAL_LINK (no reboot)
- Goal: true single-compile-unit validation (avoid stale `package\amdbc250kmd.sys`).
- Method:
  - Patch `amdbc250kmd.vcxproj` compile list to only `l2f_minimal_driver.c`.
  - Build (verify MSBuild compiles only `l2f_minimal_driver.c`).
  - Manual link from fresh `l2f_minimal_driver.obj` to unique `l2f_manual_<ts>.sys`.
  - Sign + temp kernel service start.
- Result:
  - `BUILD_EXIT=0`, `LINK_EXIT=0`, `SIGN_EXIT=0`
  - `SC_START_EXIT=0` (service reached RUNNING)
  - Unique hash: `919BF9F8FA4CE8FB721E801B257522279F9C7937077F5DC001197502F4448050`
- Interpretation:
  - `ERROR_REVISION_MISMATCH (1306)` is NOT an unavoidable project/global PE issue.
  - Prior L2/L2d/L2f(package) failures were contaminated by stale `build\Release\x64\package\amdbc250kmd.sys` (hash `14F07A...`).
  - Need strict hash-gate to always test freshly linked output artifact, not stale package copy.
- Follow-up risk:
  - Temp service `l2fmanual_<ts>` remained loaded (`NOT_STOPPABLE`) after start; no reboot performed.

## 2026-05-08 20:34 M0_FULL_KMD_ARTIFACT_GATE + M0B/M0C (no reboot)
- M0 gate script result:
  - Full `amdbc250kmd.vcxproj` rebuild returned success, but no freshly linked `.sys` with marker was produced under `build\Release\x64`.
  - Gate correctly aborted with stale-artifact warning.
- M0B diagnostics:
  - `/v:diag` trace showed compile activity only (`CL`) and no effective link output generation for KMD `.sys` in this path.
  - `RECENT_SYS_COUNT=0` after rebuild window.
- M0C corrective test (manual full-KMD link from fresh objects):
  - Objects built fresh:
    - `amdbc250_kmd.obj` hash `D1DF55D0...`
    - `amdbc250_hw_init.obj` hash `7A0F12C3...`
    - `amdbc250_fw_loader.obj` hash `8A481C73...`
  - Manual link output A: `m0c_fullkmd_<ts>.sys` with marker present.
  - A/B/C hash gate:
    - `A_HASH_POST_SIGN=B47BE0102C4692E33BFBC59537DA63E2668159C60DB325AEC9461065D6D4F6BD`
    - `B_HASH(package)=14F07A1544B60B31F3CA1955754738F9BE5AB539728F021EFF42B85A75717F92`
    - `C_HASH(System32 copy)=B47BE0102C4692E33BFBC59537DA63E2668159C60DB325AEC9461065D6D4F6BD`
    - `A_EQ_C=True`
  - Service start on exact C artifact: `SC_START_EXIT=1306` (`ERROR_REVISION_MISMATCH`, SCM 7000).
- Interpretation:
  - Stale package artifact was real and now isolated.
  - Even with verified fresh full-KMD artifact, service-load still fails 1306.
  - Root cause is inside full object set / binary contract, not only stale package handling.
- Side note:
  - Earlier `l2fmanual_20260508_202924` remains running and marked for deletion (NOT_STOPPABLE); no reboot performed.

## 2026-05-08 20:44 N_SERIES_OBJECT_BISECTION (no reboot, hash-gated)
- Harness: `N-Series-Bisection-NoReboot.ps1`
- Full KMD objects refreshed, then manual link per case with per-case marker and A/C hash gate.
- Object hashes during run:
  - `amdbc250_kmd.obj` = `B25B0B4228F3F7ABB679A87EAD51A7AD05D9DEE29CB68B72565DE86CCEBCEE5A`
  - `amdbc250_hw_init.obj` = `98441DE6EA9A988AC3F9289E444BF5D990A4F3140B32CECB05ECECEDFE71DDBB`
  - `amdbc250_fw_loader.obj` = `6915A02433D33369934E7859F1B235AB0445DBD261AB166CB4E037B52374C25A`
- Case outcomes:
  - `N0_BASE` (base stub only): link OK, start OK (`SC_START_EXIT=0`)
  - `N1_KMD_ONLY` (`kmd`): link fail (`LNK1120`) missing `Bc250HwReset/Bc250HwShutdown`
  - `N2_HW_ONLY` (`base+hw`): link fail (`LNK1120`) missing FW helper symbols
  - `N3_FW_ONLY` (`base+fw`): link OK, start OK (`SC_START_EXIT=0`)
  - `N4_HW_FW` (`base+hw+fw`): link OK, start OK (`SC_START_EXIT=0`)
  - `N5_KMD_HW` (`kmd+hw`): link fail (`LNK1120`) missing FW helper symbols
  - `N6_KMD_FW` (`kmd+fw`): link fail (`LNK1120`) missing `Bc250HwReset/Bc250HwShutdown`
  - `N7_FULL` (`kmd+hw+fw`): link OK, hash-gate OK (`A_EQ_C=True`), start FAIL `1306`
- Key differential:
  - `base+hw+fw` is loadable, but replacing `base` with `kmd` flips to `1306`.
  - This isolates failure contribution to `amdbc250_kmd.obj` path (entry/section/import/contract) rather than `hw_init/fw_loader` alone.
- Package stale confirmation remains:
  - `B_HASH(package)` stayed at `14F07A1544...` across runs and differs from tested A artifacts.
- Side-effect:
  - Several PASS probe services reported `STOPPABLE` but `sc stop` returned `1052` and were deleted (likely marked delete while still loaded).

## 2026-05-08 20:48 N8_KMD_STUBS (no reboot, hash-gated)
- Harness: `N8-KmdStubs-NoReboot.ps1`
- Build: refreshed `amdbc250_kmd.obj` from full KMD rebuild, then linked:
  - `amdbc250_kmd.obj`
  - `n8_kmd_deps_stubs.obj` (stubbed `Bc250HwInitialize/Bc250HwShutdown/Bc250HwReset`)
  - marker object
- Link/sign/hash gate: PASS
  - `A_EQ_C=True`
  - `A_POST=C8B7516053078A054E0117D1DEB7C3BDABEB8009FC9E3F0FE87331F2FF0A3CD0`
- Runtime: FAIL
  - `SC_START_EXIT=1306` (`ERROR_REVISION_MISMATCH`), SCM Event 7000 confirms mismatch.
- Dumpbin quick facts for N8A:
  - imports: `ntoskrnl.exe`, `HAL.DLL`
  - no dxgkrnl import observed in this artifact
- Interpretation:
  - `amdbc250_kmd.obj` alone (with minimal dependency stubs) is sufficient to reproduce 1306.
  - Confirms fault is localized to KMD compile unit contract (entry/init/global/import/section behavior), not to real hw/fw implementations.

## 2026-05-08 20:52 N9_ENTRYONLY trilogy (no reboot, hash-gated)
- Harness: `N9-EntryOnly-NoReboot.ps1`
- Method: source-swap `amdbc250_kmd.c` per variant, rebuild, manual-link from fresh `amdbc250_kmd.obj`, sign, A/C hash-gate, `sc start`.
- Results:
  - `N9A_ENTRYONLY_NO_DXGK`:
    - build/link/sign/hash-gate PASS
    - `SC_START_EXIT=0` (RUNNING)
  - `N9B_ENTRYONLY_DISPMPRT_NO_DXGK`:
    - build/link/sign/hash-gate PASS
    - `SC_START_EXIT=0` (RUNNING)
  - `N9C_ENTRYONLY_DXGK_MIN`:
    - build/link/sign/hash-gate PASS
    - `SC_START_EXIT=1306` (`ERROR_REVISION_MISMATCH`, SCM 7000)
- Key isolation:
  - `dispmprt.h` alone is not the trigger.
  - Introducing `DxgkInitialize` path with minimal DDI table is sufficient to reintroduce 1306.
- Artifact notes:
  - `N9B` import table is empty/minimal summary.
  - `N9C` imports include `ntoskrnl.exe` and `HAL.DLL`.
  - stale package hash remained unchanged (`14F07A...`) and is distinct from tested A artifacts.

## 2026-05-08 21:39 P0_N9C PnP-bind hash gate complete
- Executed `P0-N9C-PnpBind-Hashed-NoReboot.ps1` against `192.168.50.189`.
- Fresh N9C artifact was used end-to-end (`A=B=C` hash all equal: `C0324F5DB13EB58F9B4BC89147E8EDDF53EDDEB35AEA1B600CA491CB43CA064E`).
- PnP install succeeded (`oem2.inf`, `pnputil` exit `3010`), but runtime still fails in PnP path:
  - Kernel-PnP Event 219: `\Driver\amdbc250kmd failed to load`.
  - SetupAPI: `CM_PROB_FAILED_DRIVER_ENTRY` + `0xC0000059`.
- Conclusion: failure is not only manual `sc start` context; minimal `DxgkInitialize` contract still fails under real PnP bind.
- Next branch: `N9D/N9E/N9F` via PnP-bind hash-gated matrix.

## 2026-05-08 21:45 PnP N9D/N9E/N9F matrix complete
- Added `DriverVer` bump in PnP harness to force real per-iteration installs (fixes prior `already up-to-date` false runs).
- Verified true installs via `oem9.inf`, `oem10.inf`, `oem11.inf` and DriverStore hash match (`B_EQ_C=True`).
- Outcomes are identical across variants in proper PnP context:
  - `CM_PROB_FAILED_DRIVER_ENTRY` (ProblemCode 37 / 0x25)
  - `ProblemStatus = 0xC0000059`
  - Kernel-PnP Event 219 (`\Driver\amdbc250kmd failed to load`).
- Interpretation tightened:
  - Failure is at `DxgkInitialize`-entry contract boundary itself, not `sc start` context artifact, not callback-count delta, and not DOD-vs-non-DOD initializer path.
- Next tactical branch:
  - binary/ABI contract probes around `DXGKDDI_INTERFACE_VERSION` + header/lib alignment and minimal entry contract compiled under exact target WDK surface.

## 2026-05-08 21:51 N9R breadcrumb proof
- Added N9R variant with registry breadcrumbs pre/post `DxgkInitialize` and tested via PnP (`oem12.inf`) with hash-verified payload.
- Breadcrumbs show definitive local return status from `DxgkInitialize`:
  - `Bc250ReachedDriverEntry=1`
  - `Bc250Phase=2`
  - `Bc250DxgkStatus=0xC0000059`
- This removes remaining ambiguity: failure is inside/at `DxgkInitialize` contract acceptance, before BC-250 runtime paths.
- Q0 blocker: no local WDK sample tree found under `C:\Program Files (x86)\Windows Kits\10\Samples` on target; sample must be fetched or copied before Q0/Q1 cross-project matrix.

## 2026-05-08 21:52 Q0 sample prep update
- Pulled `microsoft/Windows-driver-samples` (sparse) and isolated `video/KMDOD` on target.
- Sample build is currently blocked by WDK property-chain/include resolution (`ntddk.h` unresolved in this shell/project context).
- This does not affect root diagnosis: N9R breadcrumbs already prove `DxgkInitialize` returns `0xC0000059` inside DriverEntry during PnP start.
- Next ABI step: run sample source through known-working BC250 project include/lib surface (cross-build) to separate project-chain vs API-contract causes.

## 2026-05-08 22:25 Version-pin matrix completed
- Ran R13/R20/R21/R27 (`0x4002/0x5023/0x6003/0xC004`) with strict no-reboot PnP hash-gate.
- All four variants still fail identically at DriverEntry boundary:
  - `ProblemStatus=0xC0000059`
  - breadcrumb `Bc250DxgkStatus=0xC0000059`
- Conclusion tightened further:
  - `DxgkInitialize` mismatch is not solved by pinning `init.Version` alone.
  - Next most valuable branch is callback-shape/contract matrix (lifecycle-only vs +QAI vs KMDOD-equivalent callback set) and/or cross-build inside sample project shape.

## 2026-05-08 22:33 Callback-shape matrix completed
- Executed S0..S5 @0x4002 plus S3/S4 controls @0xC004 via no-reboot PnP hash-gate.
- Outcome is invariant across all shapes and both init structures:
  - `ProblemStatus=0xC0000059`
  - breadcrumb `Bc250DxgkStatus=0xC0000059`
- This rules out callback-count/shape and DOD-vs-regular init struct as root cause in current build chain.
- Next branch: strict ABI parity work (project/property/import/include provenance), not more runtime callback permutations.

## 2026-05-09 12:04 ABI dump capture is now clean
- Updated `P0-N9C-PnpBind-Hashed-NoReboot.ps1`:
  - clears stale service `Parameters` before each install
  - logs all `Bc250*` and `Abi*` registry breadcrumbs
- Re-ran `T_ABI_LAYOUT_DUMP.sys` via P0 harness.
- Outcome unchanged on device: `ProblemCode=37`, `ProblemStatus=0xC0000059`, Event 219.
- ABI evidence captured reliably from live run:
  - `sizeof(DRIVER_INITIALIZATION_DATA)=0x4D0`
  - `sizeof(KMDDOD_INITIALIZATION_DATA)=0x150`
  - `DXGKDDI_INTERFACE_VERSION macro=0xC004`
  - stable field offsets recorded for DRV and DOD init tables.

## 2026-05-09 12:07 Q1 sample branch status
- Attempted Microsoft KMDOD sample build on BC-250 host (`SampleDisplay.vcxproj`).
- Build blocked by sample project surface mismatch:
  - `10.0.26100.0\km\ntddk.h` not present on target.
  - Repoint to `10.0.22000.0` still fails with `"No Target Architecture"` due mixed include/property chain.
- Decision:
  - Keep primary debugging on BC250 project surface (deterministic builds + reproducible `DxgkInitialize=0xC0000059`).
  - Treat KMDOD sample project setup as separate environment-fix task.

## 2026-05-09 12:19 Q1 milestone
- Normaliserade KMDOD-samplet till en konsekvent `10.0.19041.0` x64-surface på target (tidigare blockerad av mixed 26100/22000 chain).
- Sample-koden kompilerar nu i samma miljö där BC250-koden testas.
- Manuallänkad sample-binary kördes via befintlig hash-gated P0-harness.
- Resultat bytte felklass från `0xC0000059` till:
  - `CM_PROB_FAILED_ADD (0x1F)`
  - `ProblemStatus=0xC0000017`
- Detta är stark evidens att BC250-specifik init/build-shape är inblandad i `0xC0000059`; sample-kod passerar förbi den exakta grinden men stannar senare.

## 2026-05-09 13:24 Q2C milestone
- Ran sample DOD callback-shape matrix in same hash-gated P0 pipeline.
- Key result:
  - 28 callbacks => `DxgkInitializeDisplayOnlyDriver` returns `STATUS_SUCCESS` and device lands on post-init `CM_PROB_FAILED_ADD / 0xC0000017`.
  - 14 callbacks and 8 callbacks => `DxgkInitializeDisplayOnlyDriver` returns `0xC0000059` (back to `FAILED_DRIVER_ENTRY`).
- Conclusion:
  - `0xC0000059` is strongly tied to insufficient DOD callback surface in this environment.
  - Full sample-like callback completeness is required to pass init gate.

## 2026-05-09 13:29 Q2C prefix-bisect update
- Re-ran prefix bisect (`PFX21, PFX17, PFX19, PFX20`) on target `192.168.50.189` via same no-reboot hash-gated P0 path.
- All four prefix profiles reported:
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`
- This confirms the init gate can pass with callback prefixes down to at least 17 callbacks in sample order.
- Actionable boundary now: compare passing `PFX17` against failing `MID14` to isolate exact missing callback group (composition issue).

## 2026-05-09 13:32 Prefix-threshold update (PFX14..17)
- Ran threshold matrix (`PFX14, PFX15, PFX16, PFX17`) with no reboot + hash-gated P0.
- All four profiles passed init gate:
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`
- This narrows root cause of `MID14 -> 0xC0000059` to callback composition, not callback count.
- Next planned micro-test: `MID14 + {ResetDevice, InterruptRoutine, DpcRoutine}`.

## 2026-05-09 13:36 M14 composition result
- Executed `M14R`, `M14I`, `M14RID` on target `192.168.50.189` with no reboot + hash gate.
- Results:
  - `M14R` PASS init (`SampleDxgkStatus=0`) -> post-init `0xC0000017`.
  - `M14I` FAIL init (`SampleDxgkStatus=0xC0000059`).
  - `M14RID` PASS init (`SampleDxgkStatus=0`) -> post-init `0xC0000017`.
- Conclusion: `ResetDevice` is the critical callback for this MID14-derived composition; ISR/DPC alone are insufficient.
- Next focused probe: `MID14 + ResetDevice` as baseline while investigating `CM_PROB_FAILED_ADD / 0xC0000017`.

## 2026-05-09 13:43 O-series conclusion
- Completed O-series forensic batch (O1..O5) with callback breadcrumbs under DOD+MID14+Reset init baseline.
- Consistent result across all profiles:
  - `SampleDxgkStatus=0x00000000` (init passes)
  - Device `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `SampleO_AddEnter=1`, `SampleO_AddStatus=0xC0000017`
- No evidence of StartDevice execution affecting outcome; AddDevice fails first.
- New root blocker: AddDevice allocation/constructor path returns `STATUS_NO_MEMORY` (`0xC0000017`).
- Next targeted step: replace `BASIC_DISPLAY_DRIVER` construction with a minimal dummy devctx AddDevice path to verify whether failure is constructor-path specific vs true pool/resource exhaustion.

## 2026-05-09 13:48 P-series milestone
- Completed dummy-context isolation (`P1/P2/P3`) on target with no reboot.
- All profiles passed:
  - `DxgkInitializeDisplayOnlyDriver` success
  - `AddDevice` success (`SampleO_AddStatus=0`)
  - `StartDevice` executed (status tracked per profile)
- Device no longer fails with `CM_PROB_FAILED_ADD/0xC0000017`; new consistent state is `ProblemCode=43` (`ProblemStatus=0`).
- Strong conclusion: `0xC0000017` root cause is in `BASIC_DISPLAY_DRIVER` constructor/sample allocation path, not base AddDevice memory availability.
- Next branch should keep dummy context as known-good bringup and incrementally reintroduce constructor/runtime pieces to localize what triggers post-start Code 43.
