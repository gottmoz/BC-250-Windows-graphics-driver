# BC250 Test Matrix

## 2026-04-29

### T-001 (Path B baseline) - 2026-04-29 12:48 CEST
- Change: none (baseline current tree)
- Hypothesis: current package still reproduces Code 43 fallback
- Result: FAIL
- Evidence: `CM_PROB_FAILED_POST_START (43)` on `display.inf` fallback, no hardware adapter in D3DKMT/DXGI

### T-002 (Path A quick patch attempt) - 2026-04-29 12:58 CEST
- Change: appended BC250 IDs to `U0343170.inf` in `WT6A_INF`
- Hypothesis: package installs and binds as Navi10
- Result: FAIL
- Evidence: `pnputil /add-driver` failed before staging/install

### T-003 (Path B DRIVERCAPS non-VGA hint) - 2026-04-29 13:09 CEST
- Change: `DXGK_DRIVERCAPS.SupportNonVGA = TRUE` in `amdbc250_kmd.c` (plus zip mirror)
- Hypothesis: adapter classification/start path improves versus persistent Code 43 fallback
- Result: FAIL
- Evidence: iteration ~38.6s, bind still falls back to `display.inf` with `CM_PROB_FAILED_POST_START (43)`, no D3DKMT hardware adapter

### T-004 (Path B UMD D3D11 adapter bootstrap) - 2026-04-29 13:52 CEST
- Change: `OpenAdapter11` in `amdbc250_umd.c` routed to `Umd10OpenAdapter(..., TRUE)` instead of returning `E_NOTIMPL`
- Hypothesis: D3D11 runtime handshake improves adapter publication/retention
- Result: FAIL
- Evidence: iteration ~38.9s, bind still falls back to `display.inf` with `CM_PROB_FAILED_POST_START (43)`, no BC250 hardware adapter in D3DKMT/DXGI

### T-005 (Path B one-segment aperture experiment) - 2026-04-29 17:03 CEST
- Change: changed `DXGKQAITYPE_QUERYSEGMENT` to report one CPU-visible cache-coherent aperture segment and forced allocations/eviction to segment 0
- Hypothesis: simpler VidMM topology would avoid invalid segment contract and let the adapter remain started
- Result: FAIL - black-screen regression, reverted immediately
- Evidence: build/sign succeeded; `devcon update` returned 0; after 20s device was not Started and fallback restored `display.inf`; final state `Microsoft Basic Display Adapter`, `CM_PROB_FAILED_POST_START (43)`, but physical display stayed black. T-005 segment changes were backed out in both root and zip source trees.

### T-006 (Harness unique package/service names) - 2026-04-29 17:10 CEST
- Change: `shared/remote-iter-fast.ps1` now creates unique per-iteration KMD/UMD filenames and service name (`amdbc250kmd_tYYYY...sys`, `amdbc250umd_tYYYY...dll`, `amdbc250kmdtYYYY...`) before Inf2Cat/sign/install
- Hypothesis: no-reboot failures were caused by Windows seeing modified in-use driver files and requiring a restart
- Result: FAIL, but useful negative
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429171012.sys`; device still did not reach Started after 20s and fell back to `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 38.7s. This removes stale binary replacement as the main cause.

### T-007 (Path B skip all hardware init) - 2026-04-29 17:12 CEST
- Change: added `AMDBC250_SKIP_HW_INIT=1` and jumped directly to `CompatibilityStart` before resource query/MMIO map/firmware/ring init
- Hypothesis: current failure is caused by hardware touching during `StartDevice`
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429171143.sys`; device still did not reach Started and fallback restored `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 38.7s. Failure is before hardware init or in WDDM registration/topology/INF contract.

### T-008 (Path B no hardware init + one VidPN source/child) - 2026-04-29 17:13 CEST
- Change: kept `AMDBC250_SKIP_HW_INIT=1`, changed `AMDBC250_HEADLESS_RENDER_ONLY` from 1 to 0 so `StartDevice` reports one source and one child
- Hypothesis: Windows rejects a display-class adapter with zero VidPN sources/children
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429171316.sys`; device still did not reach Started and fallback restored `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 38.7s. Zero-output topology is not the sole blocker.

### T-009 (Path B KMD-only INF, no UMD registration) - 2026-04-29 17:15 CEST
- Change: removed UMD copy/reference from active INF (`CopyFiles` KMD only; no `InstalledDisplayDrivers`/`UserModeDriverName`), while keeping no-hardware/one-output KMD
- Hypothesis: incomplete UMD contract prevents adapter from reaching Started
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429171450.sys`; device still did not reach Started and fallback restored `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 38.4s. UMD registration is not the immediate start blocker.

### T-010 (Path B WDDM Win10 interface constant attempt) - 2026-04-29 17:16 CEST
- Change: attempted to switch `DriverInitData.Version` from `DXGKDDI_INTERFACE_VERSION_WDDM1_3` to `DXGKDDI_INTERFACE_VERSION_WIN10`
- Hypothesis: wrong DXGK interface version prevents miniport registration
- Result: BUILD FAIL, no driver installed
- Evidence: WDK 10.0.19041 headers on target do not define `DXGKDDI_INTERFACE_VERSION_WIN10`; compile failed at `amdbc250_kmd.c(65)`, target remained on `display.inf` fallback.

### T-011 (Path B WDDM 2.0 interface version) - 2026-04-29 17:18 CEST
- Change: set `DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM2_0`, with hardware still skipped and UMD still unregistered
- Hypothesis: WDDM 1.3 interface registration was incompatible with the current Windows 10 display stack
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429171811.sys`; device still did not reach Started and fallback restored `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 38.7s. Interface version alone is not the start blocker.

### T-012 (Path B QUERYSEGMENT first-call fix) - 2026-04-29 17:20 CEST
- Change: changed `DXGKQAITYPE_QUERYSEGMENT` first-call detection from `pInputData == NULL` to `pSegmentDescriptor == NULL`, returning only `NbSegment` when descriptors are not supplied; reverted interface version to WDDM 1.3
- Hypothesis: WDDM was calling QUERYSEGMENT with input data but no descriptor array, and the driver returned `STATUS_INVALID_PARAMETER` during start
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429171959.sys`; device still did not reach Started and fallback restored `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 38.9s. The fix is still worth keeping because the old branch was defensively wrong, but it did not solve PnP start alone.

### T-013 (Path B minimal display-only DDI table) - 2026-04-29 17:36 CEST
- Change: while `AMDBC250_SKIP_HW_INIT=1`, stopped registering interrupt, allocation, context, paging, render, present, preempt, and fence callbacks; kept lifecycle/query/display/VidPN callbacks only
- Hypothesis: dxgkrnl was rejecting invalid render/hardware callbacks advertised while no hardware/rings were initialized
- Result: FAIL, worse signal
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429173558.sys`, but Kernel-PnP event 219 reported `\Driver\amdbc250kmdt20260429173558 failed to load`; fallback restored `display.inf` with `CM_PROB_FAILED_POST_START (43)`; iteration 39.1s. This suggests some removed callbacks are mandatory for this miniport registration path, so T-013 will be reverted.

### T-014 (Path B extensive post-run debug harness) - 2026-04-29 17:39 CEST
- Change: restored full DDI table after T-013, kept no-hardware/one-output/KMD-only/fixed QUERYSEGMENT state, and added extensive post-run debug to `remote-iter-fast.ps1`
- Hypothesis: detailed logs would identify whether the failure is signing, ranking, service creation, CodeIntegrity, or setupapi start
- Result: FAIL, but debug improved
- Evidence: package signatures verify successfully; `oem9.inf` is best ranked for the BC250 hardware ID; setupapi stages and configures the service successfully, but the guard fallback restores `display.inf` before detailed debug runs. Harness limitation found: debug must run before fallback. Patched `Run-GuardedDriverTest.ps1` to emit pre-fallback PnP/service/event/XML debug for T-015.

### T-015 (Path B pre-fallback debug) - 2026-04-29 17:40 CEST
- Change: kept no-hardware/one-output/KMD-only/fixed QUERYSEGMENT/full DDI table state and ran the patched guard with pre-fallback PnP, service, Kernel-PnP, CodeIntegrity, and setupapi capture before reverting to `display.inf`
- Hypothesis: the pre-fallback state would identify the actual failure class before rollback hides it
- Result: FAIL, but decisive diagnostic
- Evidence: package bound to `oem9.inf` as `AMD BC-250 Graphics Adapter`; `DEVPKEY_Device_Service = amdbc250kmdt20260429174005`; `DEVPKEY_Device_ProblemCode = 43`; `DEVPKEY_Device_ProblemStatus = 0`; service binary was `\SystemRoot\System32\drivers\amdbc250kmd_t20260429174005.sys`, demand-start, load group `Video`, but `sc query` showed `STATE: STOPPED` and `WIN32_EXIT_CODE: 1077`. Kernel-PnP Configuration event 410 for `oem9.inf` reported `Problem=0x0` and `Status=0x0`; no fresh CodeIntegrity failure was present. This rules out signing, ranking, and INF staging as the immediate blocker and points at WDDM post-start/driver-type semantics.

### T-016 (Path B strict render-only DDI table) - 2026-04-29 17:44 CEST
- Change: set `AMDBC250_HEADLESS_RENDER_ONLY=1`, reported zero VidPN sources/children, stopped registering child/output/pointer/VidPN display callbacks, set render-only `SupportNonVGA=FALSE`, and disabled unsupported `SupportPerEngineTDR`
- Hypothesis: Microsoft WDDM docs allow a render-only adapter to expose render DDIs and no display DDIs, avoiding the post-start display path that currently fails
- Result: FAIL, worse signal
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429174428.sys`, but Kernel-PnP event 219 reported `\Driver\amdbc250kmdt20260429174428 failed to load`; setupapi recorded `CM_PROB_FAILED_DRIVER_ENTRY` with problem status `0xc0000059` (`STATUS_REVISION_MISMATCH`). This indicates the current WDDM 1.3 initialization table is rejected when those display callbacks are null, so the strict render-only DDI-table change was reverted for the next test.

### T-017 (Path B full DDI table, unsupported per-engine TDR disabled) - 2026-04-29 17:46 CEST
- Change: restored one-output/full display DDI registration by setting `AMDBC250_HEADLESS_RENDER_ONLY=0`, kept hardware init skipped, kept fixed QUERYSEGMENT, and left `SupportPerEngineTDR=FALSE`
- Hypothesis: post-start failed because the driver advertised per-engine TDR without implementing the required reset/status DDIs
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429174602.sys`; no fresh Kernel-PnP Event 219 was reported, setupapi showed `Restarting Devices` without a driver-entry error, but after 20s the device was still not Started and fallback restored `display.inf`. Disabling unsupported per-engine TDR avoids the T-016 driver-entry regression but does not solve the post-start Code 43 path.

### T-018 (Path B UMD registration restored) - 2026-04-29 17:47 CEST
- Change: restored UMD copy/registration in the active INF (`CopyFiles = amdbc250_Files_KM, amdbc250_Files_UM`, `InstalledDisplayDrivers`, `UserModeDriverName`, and `UserModeDriverNameWow`) while keeping one-output/full DDI/no-hardware/fixed QUERYSEGMENT/`SupportPerEngineTDR=FALSE`
- Hypothesis: the full graphics WDDM package was failing post-start because the KMD-only INF did not publish a user-mode display driver
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429174732.sys` and UMD `amdbc250umd_t20260429174732.dll`; setupapi copied both KMD and UMD and configured the service, but the device did not reach Started within 20s and fallback restored `display.inf`. UMD packaging is now more correct and should remain, but it is not the immediate Code 43 post-start blocker.

### T-019 (Path B POST/non-VGA capability disabled) - 2026-04-29 17:49 CEST
- Change: kept UMD registration restored and set `DXGK_DRIVERCAPS.SupportNonVGA = FALSE` while keeping one-output/full DDI/no-hardware/fixed QUERYSEGMENT/`SupportPerEngineTDR=FALSE`
- Hypothesis: post-start failed because the driver advertised non-VGA POST ownership support without implementing `DxgkDdiStopDeviceAndReleasePostDisplayOwnership`
- Result: FAIL
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429174919.sys` and UMD `amdbc250umd_t20260429174919.dll`; pre-fallback debug showed `DEVPKEY_Device_Service = amdbc250kmdt20260429174919`, `ProblemCode = 43`, `ProblemStatus = 0`, and `sc query` reported `STATE: STOPPED`, `WIN32_EXIT_CODE: 1077` (`service has never been started`). This rules out non-VGA capability alone and shows the service is created but not loaded by the no-reboot PnP path.

### T-020 (Path B service StartType system-start) - 2026-04-29 17:51 CEST
- Change: changed INF service `StartType` from demand-start (`3`) to system-start (`1`) while keeping UMD registration restored and the T-019 KMD caps
- Hypothesis: PnP did not load the miniport service because display miniports need a BasicDisplay-style system-start service configuration
- Result: FAIL, worse signal
- Evidence: build/sign/install succeeded with unique KMD `amdbc250kmd_t20260429175104.sys`, setupapi installed the service as `system start`, but device restart failed immediately with `CM_PROB_FAILED_ADD` and problem status `0xc00000bb` (`STATUS_NOT_SUPPORTED`). This makes system-start worse for no-reboot testing, so `StartType` was reverted to demand-start.

## T-021 - 2026-04-29 17:59 CEST - Minimal VidPN mode-set implementation
- Change: Added always-connected child, 1024x768@60 monitor/source/target mode population, stricter one-path IsSupportedVidPn.
- Build: PASS on target. KMD warning-only build; UMD PASS; package/catalog/test-signing PASS.
- Result: FAIL, but not a valid KMD-code exercise. devcon update installed oem9.inf and service amdbc250kmdt20260429175903, then status stayed Code 43 / CM_PROB_FAILED_POST_START.
- Evidence: Pre-fallback Service Control showed STATE STOPPED and WIN32_EXIT_CODE 1077; DEVPKEY_Device_ProblemStatus=0; Kernel-PnP event 410 Problem=0 Status=0. The miniport service was never loaded.
- Decision: Patch harness to force pnputil /restart-device after devcon update before judging Started state.

## T-022 - 2026-04-29 18:01 CEST - Forced post-bind pnputil restart
- Change: Same KMD as T-021; guarded runner now calls `pnputil /restart-device` after devcon update.
- Build: PASS on target. KMD and UMD PASS; package/catalog/test-signing PASS.
- Result: FAIL. `post-bind restart exit code: 0`, but adapter remained Code 43 / CM_PROB_FAILED_POST_START and fallback restored display.inf.
- Evidence: Recent events still only show SCM service install and Kernel-PnP configuration success. No CodeIntegrity/LiveKernel/DxgKrnl evidence. SetupAPI still says restart required and Start attempted, but no specific driver-start status.
- Decision: Next harness iteration should use explicit `devcon restart <instance>` and capture service/query output before fallback. If still no load evidence, test disable/enable or a one-time reboot only with user approval.

## T-023 - 2026-04-29 18:02 CEST - Forced devcon instance restart
- Change: Same KMD; runner added `devcon restart @<instance>` after `pnputil /restart-device`.
- Build: PASS on target. KMD/UMD/package/signature all PASS.
- Result: FAIL. `post-bind devcon restart exit code: 0`, but adapter remained Code 43 / CM_PROB_FAILED_POST_START and fallback restored display.inf.
- Evidence: Still no CodeIntegrity, LiveKernel, DxgKrnl, or SCM service-load error. Only service installation and PnP config events. This still looks like stale PnP problem state or reboot-required display stack replacement, not a KMD callback failure.
- Decision: Next run uses no-reboot disable/enable after binding to force a fresh PnP start without full reboot.

## T-024 - 2026-04-29 18:04 CEST - No-reboot disable/enable after bind
- Change: Same KMD; runner added `pnputil /disable-device /force` and `/enable-device` after update/restart.
- Build: PASS on target. KMD/UMD/package/signature all PASS.
- Result: FAIL. Disable and enable both returned 0, but adapter remained Code 43 / CM_PROB_FAILED_POST_START and fallback restored display.inf.
- Evidence: Still only SCM service-install and PnP config events; no CodeIntegrity/LiveKernel/DxgKrnl error. This strongly suggests the active display stack replacement is not taking effect no-reboot, or the failure is hidden before the display miniport service records a normal load failure.
- Decision: Next diagnostic run explicitly calls `sc start <unique-service>` before fallback to test whether the signed `.sys` image can be loaded at all and capture exact service-start error.

## T-025 - 2026-04-29 18:05 CEST - Explicit service image-load diagnostic
- Change: Same KMD; runner explicitly calls `sc start <unique-service>` after bind/restart/disable/enable.
- Build: PASS on target. KMD/UMD/package/signature all PASS.
- Result: FAIL for adapter start, but diagnostic improved: `sc start amdbc250kmdt20260429180544` returned exit code 0, proving the signed `.sys` can be loaded by SCM.
- Evidence: Adapter remained Code 43 / CM_PROB_FAILED_POST_START after service load; fallback restored display.inf. Need inspect service query in pulled guarded log to see whether service remained RUNNING or stopped.
- Decision: The fault is no longer signature/image-load. Next likely paths are PnP display miniport binding semantics, INF display-class service parameters, or reboot-required display stack replacement.

## T-025 log follow-up - 2026-04-29 18:06 CEST
- Pulled evidence: `sc start` loaded the KMD and service remained RUNNING (`STATE=4`, `WIN32_EXIT_CODE=0`).
- Interpretation: The binary/signature/DriverEntry path is good enough to load. The PCI display adapter still remains Code 43, so the missing link is PnP binding / Dxgk device start, not image loading.
- Next test: restart the device after the explicit service load so PnP can bind against an already loaded driver object.

## T-026 - 2026-04-29 18:07 CEST - Restart after explicit service load
- Change: Same KMD; after `sc start` loads the unique kernel service and it remains RUNNING, runner restarts the PCI device again with both devcon and pnputil.
- Build: PASS on target. KMD/UMD/package/signature all PASS.
- Result: FAIL. Adapter remains Code 43 / CM_PROB_FAILED_POST_START. Fallback restored display.inf.
- Evidence: KMD service can run (`sc start` exit 0, service RUNNING), but PnP still does not bind/start the display adapter no-reboot. No CodeIntegrity/LiveKernel/DxgKrnl error appeared.
- Decision: No-reboot install loop is exhausted. Continue static WDDM correctness fixes and build verification. Full runtime validation likely requires a guarded reboot/install path, but not doing that without approval because rebooting with the driver active has locked the machine before.

## T-027 - 2026-04-29 18:16 CEST - Build-only cleanup after skill/tool review
- Change: Created local `bc250-driver` Codex skill and cleaned KMD compatibility-start build path so AMDBC250_SKIP_HW_INIT=1 compiles only the fallback path instead of unreachable MMIO/hardware code. Cast PM4 indirect-buffer packet header to ULONG.
- Build: PASS on target with explicit MSBuild path. KMD_EXIT=0, UMD_EXIT=0. No KMD warnings shown in minimal build output.
- Runtime: Not run. No driver bind and no reboot by design.
- Result: PASS for build hygiene. This makes future warning output meaningful and preserves the safe BasicDisplay target state.
- Decision: Next useful driver patch should add stronger CommitVidPn validation/logging or prepare an explicitly approved guarded reboot/runtime test; repeated no-reboot bind loops are already exhausted.

## External reference - Keshas-dev/AMD-bc-250-win - 2026-04-30 00:32 CEST
- URL: https://github.com/Keshas-dev/AMD-bc-250-win
- Clone: E:\world view\refs\AMD-bc-250-win
- Commit: 7828213c1b73c963fb142292fecd7ea24d9a6f06
- Contents: README.md only. No driver source, INF, build project, binary, firmware, logs, or issues.
- Usefulness: Confirms documentation-level assumptions only. It does not provide a fix for Code 43 / PnP binding.
- Relevant notes copied into strategy: CP microcode load remains a likely future hardware path; D3D11/D3D12/Vulkan are not available without a real UMD; current work should still focus on KMD PnP/VidPN start stability before acceleration.

## External reference - PS5 DevWiki - 2026-04-30 00:33 CEST
- Main: https://www.psdevwiki.com/ps5/
- GPU page: RDNA2, 2.23GHz, 10.28 TFLOPS. Useful only as high-level confirmation.
- Hardware/Memory pages: 16GB GDDR6, 256-bit, 448GB/s; matches BC-250 memory-class assumptions but not driver-specific.
- PUP page: outer PUP magic `SLB2`, file table at `0x30`; update phases include oberon_sec_ldr_c0.bin, kernel.bin, ssd0.system_b, ssd0.system_ex_b, and several encrypted payloads. This matches our parser and explains why the local PUP only exposed an encrypted inner blob.
- Build Strings page: VBIOS strings include AMD ATOMBIOS AMDObrGeneri for Oberon; useful search term if a decrypted VBIOS dump is obtained.
- Devices page: /dev/gc GPU command, /dev/dbggc_control debug GPU, /dev/mp1 SMU clock device, /dev/pup_update0 decrypt/verify IOCTLs. This suggests decryption is console-service-mediated, not directly extractable from the downloaded PUP.
- Driver action: no immediate code merge. Add search terms for future decrypted PS5 dumps: AMDObrGeneri, ATOMBIOSBK-AMD, oberon_sec_ldr_c0.bin, /dev/gc, mp1, PUP_UPDATER_DECRYPT_SEGMENT, GC, SMU, DCN, PFP, MEC.

## External artifact - decrypted PS5 PUP - 2026-04-30 00:49 CEST
- Input: C:\Users\jimmy\Downloads\PS5UPDATE1.PUP.dec
- Header: PUP fragment magic `0xEEF51454`, 26 segment entries.
- Tool added: `tools/parse_ps5_decrypted_pup.py`, ports zecoxao/ps5-pup-unpacker behavior for normal, zlib, and blocked entries.
- Extracted: kernel.bin, `titania.bls`, oberon_sec_ldr_c0.bin, oberon_sec_ldr_d0.bin, ssd0.system_b, ssd0.system_ex_b.
- Filesystem result: ssd0.system_b and ssd0.system_ex_b are exFAT images. Parsed 666 files in system_b and 2276 files in system_ex_b.
- Graphics paths found: libSceAgc*, libSceGnmDriver*, libSceVideoOut*, /sys/AgcCompositor.elf, /sys/gpudump.elf, libSceGLSlim*.
- Limitation: extracted graphics files are still SELF/SPRX high-entropy containers with `0xEEF51454`; no plain AMD firmware/register tables found.
- Driver impact: no direct code change; useful only as naming/layout reference unless SELF contents can also be decrypted.

## T-028 - 2026-04-30 00:56 CEST - Prefer WDDM2.0 registration
- Change: In DriverEntry, switched DriverInitData.Version to prefer DXGKDDI_INTERFACE_VERSION_WDDM2_0 with compile-time fallback to WDDM1_3.
- Build: PASS on target. KMD/UMD/package/signature all PASS.
- Runtime: FAIL. No-reboot guarded cycle completed in ~46.6s (ITERATION_SECONDS=46.6). Adapter still failed to start and immediately fell back to display.inf with Code 43 / CM_PROB_FAILED_POST_START.
- Evidence: Service install/load path still succeeds (sc start exit 0), but PnP status remains failure during bind/restart (Device Status: 0x01802400 [0x2b - 0x00000000]).
- Decision: WDDM version mismatch alone is not the blocker.

## T-029 - 2026-04-30 00:59 CEST - Add QUERYSEGMENT2/QUERYSEGMENT3 responses
- Change: Implemented QueryAdapterInfo cases for DXGKQAITYPE_QUERYSEGMENT2 and DXGKQAITYPE_QUERYSEGMENT3 with minimal 2-segment descriptors and paging buffer metadata.
- Build: PASS on target.
- Runtime: FAIL. No-reboot guarded cycle completed in ~43.2s (ITERATION_SECONDS=43.2). Adapter still failed to start and reverted to display.inf Code 43.
- Evidence: Same failure signature as previous run. Best-ranked BC250 INF is selected and installed; service binary is copied and service entry created; start still does not publish a working display/render adapter.
- Decision: Segment query coverage was not the missing piece for start. Next likely path is missing mandatory startup callbacks/adapter caps consistency rather than INF ranking or package/signing.

## T-030 - 2026-04-30 01:12 CEST - Fast cycle recovered, runtime still Code 43
- Change: Patched shared/remote-iter-fast.ps1 build invocation to avoid MSVC PDB lock (/m:1, /nodeReuse:false, /FS, single-proc compile settings).
- Build: PASS on target for KMD and UMD with zero errors.
- Runtime: FAIL. No-reboot guarded cycle completed in 45.7s (ITERATION_SECONDS=45.7). Adapter still falls back to display.inf with CM_PROB_FAILED_POST_START.
- Evidence:
- SetupAPI: Device Status: 0x01802400 [0x2b - 0x00000000] and Configure Driver Package ... exit(0x00000bc3) with Restart required for any devices using this driver.
- SCM 7045 confirms unique miniport service gets installed (mdbc250kmd_t20260430011036.sys).
- dxgi/kmt after run: only Microsoft Basic Render adapters; no BC-250 render/display publication.
- Additional bug found: package INF still contains InstalledDisplayDrivers = amdbc250umd (base name) while UserModeDriverName is unique DLL filename, causing a UMD registry mismatch.
- Decision: Next run will patch INF rewrite logic so InstalledDisplayDrivers and UserModeDriverName* use the same unique base consistently.

## T-031 - 2026-04-30 08:18 CEST - KMD instrumentation patch build gate
- Change: Added AddDevice/StartDevice trace enrichment and converted DispatchIoRequest stub to return success with status block update.
- Result: BUILD FAIL in first pass due to undefined ERROR_INVALID_FUNCTION in kernel build (C2065).
- Safety: No driver bind occurred; target remained on BasicDisplay safe baseline.
- Fix applied immediately: replaced status constant with literal 1 and reran.

## T-032 - 2026-04-30 08:20 CEST - Instrumented KMD runtime test
- Change set under test: AddDevice/StartDevice instrumentation + DispatchIoRequest success stub + prior INF UMD name alignment.
- Build: PASS (KMD 1 warning, UMD 0 warnings), signed package generated.
- Runtime: FAIL, unchanged behavior. Fast no-reboot cycle completed in 43.7s (ITERATION_SECONDS=43.7), adapter returns to display.inf / CM_PROB_FAILED_POST_START after guarded bind attempt.
- Evidence:
- BC250 package remains best ranked and installs (oem21.inf, service created and sc start succeeds).
- SetupAPI still reports Device Status: 0x01802400 [0x2b - 0x00000000] and Configure Driver Package exit(0x00000bc3) with restart-required semantics.
- DXGI/KMT enumeration still exposes only Microsoft Basic Render adapters after test.
- Conclusion: packaging and basic service load path are working; failure remains in display miniport start/publish path, not signature/INF ranking.

## T-033 - 2026-04-30 16:33 CEST - Fresh signed Radeon package (u0397406_bc250) selected but fails start
- Change: Built fresh package clone with unique INF name u0397406_bc250.inf, injected BC-250 IDs, regenerated CAT via Inf2Cat, signed CAT, and staged package.
- Signing gate: PASS (INF2CAT_EXIT=0, SIGN_CAT_EXIT=0, SetupAPI Signer Score = Authenticode).
- Selection: PASS. Package is best-ranked for PCI BC-250 (oem9.inf, rank  0CF0001, matching ID PCI\\VEN_1002&DEV_13FE&SUBSYS_00001022).
- Runtime: FAIL. AMD adapter start fails (CM_PROB_FAILED_POST_START for PCI instance) and a ROOT\\DISPLAY\\0000 node appears with CM_PROB_FAILED_ADD (service mduw23g).
- Evidence highlights:
- SetupAPI shows Section Name = ati2mtag_Navi10 and Add Service: amduw23g with mdkmdag.sys path from DriverStore.
- Driver status table can show AMD as best-ranked while active installed display remains display.inf / BasicDisplay after fallback/recovery.
- Decision: INF rank/selection is no longer the blocker. Current blocker moved to AMD runtime start path on BC-250 (mduw23g/amdkmdag initialization failure after bind).

## T-034 - 2026-04-30 16:56 CEST - Signed section-map sweep (ti2mtag_Navi14, ti2mtag_Navi21, ti2mtag_Legacy)
- Change: Three signed-only iterations using the same patched Radeon package flow, varying only install section mapping for BC-250 IDs.
- Signing gate: PASS for all iterations (Inf2Cat + CAT sign + verify).
- Results:
- ti2mtag_Navi14: PCI adapter -> CM_PROB_FAILED_POST_START (oem9.inf, service mduw23g, code 43). Rollback -> display.inf, CM_PROB_NONE.
- ti2mtag_Navi21: PCI adapter -> CM_PROB_FAILED_POST_START (oem9.inf, service mduw23g, code 43). Rollback -> display.inf, CM_PROB_NONE.
- ti2mtag_Legacy: PCI adapter -> CM_PROB_FAILED_POST_START (oem9.inf, service mduw23g, code 43). Rollback -> display.inf, CM_PROB_NONE.
- Interpretation: failure signature is section-independent across tested mappings; BC-250 still fails in AMD runtime start path after successful signed bind.

## T-035 - 2026-04-30 17:02 CEST - Signed map extensions (ti2mtag_Navi23, ti2mtag_Mendocino, ti2mtag_Navi31)
- Change: Extended signed-only mapping sweep to additional install sections not previously tested.
- Signing gate: PASS (same signed workflow as T-034).
- Results:
- ti2mtag_Navi23 -> CM_PROB_FAILED_POST_START on PCI adapter (oem9.inf, mduw23g, code 43), rollback success.
- ti2mtag_Mendocino -> CM_PROB_FAILED_POST_START on PCI adapter (oem9.inf, mduw23g, code 43), rollback success.
- ti2mtag_Navi31 -> CM_PROB_FAILED_POST_START on PCI adapter (oem9.inf, mduw23g, code 43), rollback success.
- Interpretation: across tested AMD section families (legacy/APU/RDNA2/RDNA3), failure signature is invariant; INF section remap alone is not the fix.

## T-036 - 2026-04-30 17:26 CEST - Signed map continuation (ti2mtag_Navi24, ti2mtag_Phoenix)
- Signing gate: PASS (same strict signed workflow).
- ti2mtag_Navi24 -> CM_PROB_FAILED_POST_START (oem9.inf, mduw23g, code 43), rollback to display.inf success.
- ti2mtag_Phoenix -> CM_PROB_FAILED_POST_START (oem9.inf, mduw23g, code 43), rollback to display.inf success.
- Conclusion unchanged: runtime failure signature persists across additional mapping families.

## T-037 - 2026-04-30 17:35 CEST - Signed map continuation (ati2mtag_Navi32, ati2mtag_DragonRange, ati2mtag_Rembrandt)
- Signing gate: PASS for all three iterations.
- ati2mtag_Navi32 -> CM_PROB_FAILED_POST_START (oem9.inf, amduw23g, code 43), rollback success to display.inf.
- ati2mtag_DragonRange -> CM_PROB_FAILED_POST_START (oem9.inf, amduw23g, code 43), rollback success to display.inf.
- ati2mtag_Rembrandt -> CM_PROB_FAILED_POST_START (oem9.inf, amduw23g, code 43), rollback success to display.inf.
- Conclusion: model-section remap remains invariant failure across additional sections.

## T-038 - 2026-04-30 17:43 CEST - Runtime telemetry harness (Navi10 baseline)
- Added signed test harness with 20s post-bind delay and targeted System event extraction before rollback.
- Result: CM_PROB_FAILED_POST_START (oem9.inf, amduw23g, code 43), rollback success.
- Event slice: Service Control Manager 7040 start-type transitions observed for AMD services around bind window.
- Note: one earlier concurrent-run attempt invalidated by staging-file lock and was discarded.

## T-039 - 2026-04-30 17:44 CEST - Runtime telemetry with AMD helper services forced demand
- Variant: same signed Navi10 bind, plus stop/config demand for AMD Crash Defender Service and AMD External Events Utility before bind.
- Result: unchanged CM_PROB_FAILED_POST_START (oem9.inf, amduw23g, code 43), rollback success.
- Conclusion: helper-service start-type perturbation does not resolve post-start failure; blocker remains in core AMD miniport/runtime init path.

## T-040 - 2026-04-30 17:47 CEST - Pre-force mduw23g auto+running before signed Navi10 bind
- Pre-step: sc config amduw23g start= auto and sc start amduw23g succeeded before test.
- Runtime: unchanged failure after signed bind (CM_PROB_FAILED_POST_START, oem9.inf, mduw23g, code 43).
- Event slice: installer/bind flow flips mduw23g back to demand and toggles AMD External Events service start type.
- Rollback: success to display.inf / CM_PROB_NONE.
- Conclusion: pre-start policy override is not sufficient; failure is in AMD runtime init after bind.

## T-041 - 2026-04-30 17:58 CEST - CM_PROB baseline recovery sequence
- Goal: resolve stuck display.inf + Code 43 baseline without reboot.
- Recovery actions: remove ROOT\\DISPLAY\\0000, uninstall stale oem9/oem21, rescan, remove/re-enumerate PCI display instance, rebind display.inf, restart device.
- Result: baseline restored to CM_PROB_NONE, display.inf, BasicDisplay.
- Impact: enables continued fast headless iteration after occasional stuck-post-start state.

## T-042 - 2026-04-30 17:59 CEST - Post-recovery validation runs (Navi10 + Navi32)
- Signed tests after T-041 recovery:
- ti2mtag_Navi10: fail signature unchanged (CM_PROB_FAILED_POST_START, mduw23g), rollback to CM_PROB_NONE success.
- ti2mtag_Navi32: same fail signature, rollback to CM_PROB_NONE success.
- Conclusion: recovery fixed baseline only; AMD runtime start failure remains unchanged.

## T-043 - 2026-04-30 18:01 CEST - Safe iterator wrapper with auto-recovery
- Added 	ools/bc250-safe-iterate.ps1 and deployed to target as C:\Users\Public\bc250-safe-iterate.ps1.
- Behavior: pre-check baseline; auto-recover if not display.inf+code0; run signed map test; post-check and auto-recover if needed.
- Validation run (ti2mtag_DragonRange): expected Code 43 on AMD bind, rollback to CM_PROB_NONE confirmed.

## T-044 - 2026-04-30 19:08 CEST - Fast short-window continuity batch A
- Maps: ti2mtag_Raphael, ti2mtag_Phoenix, ti2mtag_Navi33 via c250-safe-iterate.ps1.
- All three: AMD bind -> CM_PROB_FAILED_POST_START (oem9.inf, mduw23g, code 43), rollback -> display.inf + CM_PROB_NONE.
- Iteration windows:
- Raphael: 19:08:14 -> 19:09:09
- Phoenix: 19:09:09 -> 19:10:10
- Navi33: 19:10:11 -> 19:11:13
- Remote continuity: SSH remained responsive throughout run windows (no headless disconnect event).

## T-045 - 2026-04-30 19:14 CEST - Fast short-window continuity batch B
- Maps: ti2mtag_Raphael, ti2mtag_Phoenix, ti2mtag_DragonRange, ti2mtag_Navi10.
- Each iteration result: AMD bind -> CM_PROB_FAILED_POST_START (oem9.inf, mduw23g, code 43).
- Each rollback: display.inf + CM_PROB_NONE.
- Time windows:
- Raphael: 19:14:38 -> 19:15:41
- Phoenix: 19:15:41 -> 19:16:44
- DragonRange: 19:16:45 -> 19:17:52
- Navi10: 19:17:53 -> 19:19:05
- Continuity: SSH stable through all activation windows.
## 2026-05-02

- 16:01 CEST - Patch A1: `DriverInitData.Version=DXGKDDI_INTERFACE_VERSION`, `DxgkDdiQueryInterface=enabled`, `DxgkDdiControlInterrupt=enabled`.
  - Result: FAIL bind.
  - SetupAPI: `CM_PROB_FAILED_DRIVER_ENTRY (0x25)`, status `0xC0000059`.
  - Kernel-PnP Event 219 status decimal `3221226341` (`0xC0000059`).
  - Recovery: automatic fallback to `display.inf`, device `Started`.
  - Iteration time: `45.4s`.

- 16:03 CEST - Patch A2: interface/caps pinning to WDDM2.0/1.3 (`DriverInitData.Version` + `DRIVERCAPS.WDDMVersion` + `WDDMDEVICECAPS.WDDMVersion`).
  - Result: FAIL bind.
  - SetupAPI: `CM_PROB_FAILED_DRIVER_ENTRY (0x25)`, status `0xC0000059`.
  - Kernel-PnP Event 219 status decimal `3221226341` (`0xC0000059`).
  - Recovery: automatic fallback to `display.inf`, device `Started`.
  - Iteration time: `42.2s`.
- 16:21 CEST - V1_qi0_ci0_pc0_rk0 (QueryInterface=NULL, ControlInterrupt=NULL, Preempt=NULL, RenderKm=NULL)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 46.6s.

- 16:22 CEST - V2_qi1_ci0_pc0_rk0 (QueryInterface=ON, ControlInterrupt=NULL)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.7s.

- 16:22 CEST - V3_qi0_ci1_pc0_rk0 (QueryInterface=NULL, ControlInterrupt=ON)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 41.8s.

- 16:23 CEST - V4_qi1_ci1_pc0_rk0 (QueryInterface=ON, ControlInterrupt=ON)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 41.7s.

- 16:24 CEST - V5_qi1_ci1_pc1_rk0 (Preempt=ON)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 41.9s.

- 16:25 CEST - G1_headless1_skip1
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.5s.

- 16:26 CEST - G2_headless1_skip0
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 41.8s.

- 16:26 CEST - G3_headless0_skip1
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 44.3s.
## 2026-05-03 ABI Batch

- 09:44 CEST - A1_wddm13_qi0_ci0
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 48.5s.

- 09:45 CEST - A2_wddm13_qi1_ci0
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 44.0s.

- 09:46 CEST - A3_wddm20_qi0_ci0
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.2s.

- 09:47 CEST - A4_wddm20_qi1_ci1
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.7s.

- 09:47 CEST - A5_sdkver_qi0_ci0
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.5s.
## 2026-05-03 Entry Stub Batch

- 09:50 CEST - E1_core_only (endast core lifecycle DDIs)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.1s.

- 09:51 CEST - E2_core_plus_query (core + QueryAdapterInfo/QueryInterface)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.5s.

- 09:51 CEST - E3_core_plus_mem
  - Result: INVALID RUN (batch-script ersatte fel rad och gav build error: `DriverInitData undeclared`), 0.9s.

- 09:53 CEST - E3b_core_query_no_mem (ersättningskörning)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.3s.
## 2026-05-03 ABI Batch 2

- 10:06 CEST - B1_sdkver_coremin
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.9s.

- 10:07 CEST - B2_wddm13_coremin
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.8s.

- 10:08 CEST - B3_wddm20_coremin
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.3s.

- 10:09 CEST - B4_wddm13_qi_only
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 46.9s.

- 10:09 CEST - B5_wddm13_qi_ci
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.7s.
## 2026-05-03 Linker/PE Batch v2

- 10:15 CEST - D1_baseline
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.9s.

- 10:15 CEST - D2_nodef_off (`IgnoreAllDefaultLibraries=false`)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.6s.

- 10:16 CEST - D3_pe61 (`/OSVERSION:6.01 /SUBSYSTEM:NATIVE,6.01`)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.6s.

- 10:17 CEST - D4_nodef_off_pe61 (kombinerad)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 42.6s.
- 10:47 CEST - ABI fix: `DXGKRNL_INTERFACE` size-safe copy in `DxgkDdiStartDevice` + build-env repair in `amdbc250kmd.vcxproj` (x64/shared include)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.8s.
- 10:49 CEST - ABI compile-check pass + `DXGKRNL_INTERFACE` size-safe copy
  - Build: PASS (DDI type-compat checks compiled, no signature mismatch errors).
  - Runtime: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.3s.
## 2026-05-03 KMDOD-style Profile Batch v2

- 11:26 CEST - Q1_kmdod_min
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.7s.

- 11:26 CEST - Q2_plus_query
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.1s.

- 11:27 CEST - Q3_plus_mem
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.2s.

- 11:28 CEST - Q4_plus_render
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.2s.
- 11:30 CEST - Q1_kmdod_min (rerun with fixed batch script)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.9s.

- 11:31 CEST - Q2_plus_query (rerun)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.4s.

- 11:31 CEST - Q3_plus_mem (rerun)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.4s.

- 11:32 CEST - Q4_plus_render (rerun)
  - Result: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, status `0xC0000059`, 43.4s.
## 2026-05-03 Init-Contract Batch

- 11:39 CEST - R1_v13_qiqa_intr_on
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 44.2s.

- 11:40 CEST - R2_v13_qiqa_intr_off
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 43.5s.

- 11:40 CEST - R3_v13_qiqa_off_intr_off
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 43.5s.

- 11:41 CEST - R4_v20_qiqa_intr_off
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 43.7s.

- 11:42 CEST - R5_sdkdefault_qiqa_intr_off
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 44.3s.

- 11:43 CEST - R6_v20_qiqa_off_intr_off
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 43.8s.
## 2026-05-03 Init API A/B Batch

- 13:21 CEST - AB1_dxgk_baseline
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 60.6s.

- 13:22 CEST - AB2_dxgk_sdkver
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 60.1s.

- 13:23 CEST - AB3_dod_vsync_on
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 60.1s.

- 13:24 CEST - AB4_dod_vsync_off
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status  xC0000059, 60.1s.

- 13:26 CEST - Filter/stack probe
  - Result: NO FILTER CONFLICT found.
  - Device/class UpperFilters and LowerFilters are empty.
  - Active fallback service remains BasicDisplay.
## 2026-05-03 Interface Version Matrix Batch

- 13:36 CEST - VM1_wddm1_3
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.3s.

- 13:37 CEST - VM2_wddm2_0
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:38 CEST - VM3_wddm2_1
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:39 CEST - VM4_wddm2_2
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:40 CEST - VM5_wddm2_3
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:41 CEST - VM6_win8
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:42 CEST - VM7_literal_0x4002
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:43 CEST - VM8_literal_0x5023
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:44 CEST - Post-batch safe-state check
  - Result: PASS. Device reverted to Microsoft Basic Display Adapter (display.inf, BasicDisplay, ProblemCode 0).
## 2026-05-03 Compile-Time DXGK Version Batch

- 13:48 CEST - CV1_compile_default
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.3s.

- 13:49 CEST - CV2_compile_wddm1_3
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:50 CEST - CV3_compile_wddm2_0
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:51 CEST - CV4_compile_wddm2_1
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:52 CEST - CV5_compile_win8
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, status 0xC0000059, 60.1s.

- 13:53 CEST - Post-batch safe-state check
  - Result: PASS. Device reverted to Microsoft Basic Display Adapter (display.inf, BasicDisplay, ProblemCode 0).
## 2026-05-03 DriverEntry Gate Re-Run + PnP Status Decode

- 13:56 CEST - GATE1_baseline
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, SetupAPI status 0xC0000059.

- 13:57 CEST - GATE2_return_success (skip DxgkInitialize, return STATUS_SUCCESS)
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, SetupAPI status 0xC0000059.

- 13:58 CEST - GATE3_return_not_supported (skip DxgkInitialize, return STATUS_NOT_SUPPORTED)
  - Result: FAIL, CM_PROB_FAILED_DRIVER_ENTRY, SetupAPI status 0xC0000059.

- 13:59 CEST - Event-log decode (Kernel-PnP ID 219)
  - FailureName values match each generated service (amdbc250kmdt*).
  - EventData.Status = 0xC0000365 (STATUS_FAILED_DRIVER_ENTRY).
  - Note: SetupAPI problem status remains 0xC0000059 in parallel.
## 2026-05-07 Step 1/2/3 Headless Batch (UMA + Failmap + Memory-Only)

- 09:38 CEST - RB1_h1_s1
  - Variant: headless=1, skipHw=1.
  - Result: FAIL signature, Kernel-PnP Problem Status 0xC00000E5.
  - Recovery: PASS (display.inf / BasicDisplay / CM_PROB_NONE).

- 09:40 CEST - RB2_h1_s0
  - Variant: headless=1, skipHw=0.
  - Result: FAIL signature, Kernel-PnP Problem Status 0xC00000E5.
  - Recovery: PASS.

- 09:43 CEST - RB3_h0_s1
  - Variant: headless=0, skipHw=1.
  - Result: Alternate failure signature, Problem 0x15 with Status 0x0.
  - Recovery: PASS.

- 09:46 CEST - RB4_h0_s0
  - Variant: headless=0, skipHw=0.
  - Result: FAIL signature, Kernel-PnP Problem Status 0xC00000E5.
  - Recovery: PASS.

- 10:09 CEST - M01_1024MB
  - Variant: reportedVramMb=1024 (headless=1, skipHw=1 fixed).
  - Result: FAIL signature, Problem Status 0xC00000E5.
  - Recovery: PASS.

- 10:12 CEST - M02_2048MB
  - Variant: reportedVramMb=2048.
  - Result: FAIL signature, Problem Status 0xC00000E5.
  - Recovery: PASS.

- 10:16 CEST - M03_4096MB
  - Variant: reportedVramMb=4096.
  - Result: Alternate failure signature, Problem 0x15 with Status 0x0.
  - Recovery: PASS.

- 10:19 CEST - M04_8192MB
  - Variant: reportedVramMb=8192.
  - Result: FAIL signature, Problem Status 0xC00000E5.
  - Recovery: PASS.

- Notes:
  - Every iteration was signed, guarded, and baseline-restored before next reboot.
  - No stable bind observed in this batch.
## 2026-05-07 Continued Headless Iterations (pre-autoloop)

- 11:08 CEST - M05_4096MB_now
  - Variant: headless=1, skipHw=1, reportedVramMb=4096.
  - Result: Problem 0x15, Problem Status 0x0.
  - Recovery: PASS (display.inf / BasicDisplay / CM_PROB_NONE).

- 11:12 CEST - NT00_smoke_pb128k_w13_u0
  - Variant: reportedVramMb=4096, pagingBufferBytes=131072, wddmCapsLevel=13, umaFlagsProfile=0.
  - Result: Problem 0x15, Problem Status 0x0.
  - Recovery: PASS.
## 2026-05-07 Error Decode + NT05 Fix Validation

- 21:24 CEST - NT05_retest_after_fix
  - Variant: headless=1, skipHw=1, reportedVramMb=4096, pagingBufferBytes=65536, wddmCapsLevel=20, umaFlagsProfile=0.
  - Result: full run completed after compile-fix, event signature `Problem 0x0 / Status 0xC00000E5`.
  - Recovery: PASS (display.inf / BasicDisplay / CM_PROB_NONE).
## 2026-05-07 Forensic DriverEntry Contract Runs (Timestamped)

- 21:41 CEST - FORENSIC_A1_INITCONTRACT
  - Variant: headless=1, skipHw=1, eportedVramMb=4096, existing DriverEntry contract + new telemetry scaffold.
  - Result: Problem 0x15 / Problem Status 0x0 in event 411 for oem5.inf.
  - Forensics: System/SetupAPI still showed CM_PROB_FAILED_DRIVER_ENTRY /  xC0000059 and SCM "Indicates two revision levels are incompatible" in nearby timestamps.

- 21:44 CEST - FORENSIC_A2_IFACEVER
  - Variant: same runtime knobs; DriverEntry switched to Version=DXGKDDI_INTERFACE_VERSION with fallback branches retained.
  - Result: Problem 0x0 / Problem Status 0xC00000E5 in event 411 for oem5.inf.
  - Forensics: SetupAPI at 21:44:53 still logged CM_PROB_FAILED_DRIVER_ENTRY /  xC0000059; SCM 7000 revision incompatibility still present.

- 21:50 CEST - FORENSIC_A3_STRICT_DXGK_RULE
  - Variant: same runtime knobs; strict Microsoft contract form in DriverEntry (RtlZeroMemory, direct init.Version = DXGKDDI_INTERFACE_VERSION, return exact DxgkInitialize status).
  - Result: Problem 0x15 / Problem Status 0x0 in event 411 for oem5.inf.
  - Forensics snapshot window (last 10 min): no fresh  xC0000059 or SCM 7000 revision-incompatible event captured; classification appears shifted away from explicit FAILED_DRIVER_ENTRY signature.
  - Recovery: PASS baseline (display.inf / BasicDisplay / CM_PROB_NONE).
- 21:53 CEST - FORENSIC_A4_MINCALLBACKS
  - Variant: strict DriverEntry rule retained + minimal callback registration set in DriverEntry (only core lifecycle/power/interrupt + QueryAdapterInfo; advanced render/context/VidPn callbacks left NULL by zero-init).
  - Result: Problem 0x15 / Problem Status 0x0 in event 411 for oem5.inf.
  - Forensics window (8 min): no CM_PROB_FAILED_DRIVER_ENTRY, no  xC0000059, no SCM 7000 revision-incompatible entry observed.
  - Recovery: PASS baseline (display.inf / BasicDisplay / CM_PROB_NONE).
- 21:57 CEST - FORENSIC_A5_USER_MINSET
  - Variant: DriverEntry callback-set exakt enligt användarspec (core lifecycle + SetPowerState + Unload + QueryAdapterInfo; QueryInterface/Interrupt/Dpc/render/context/memory DDIs explicita NULL).
  - Result: Problem 0x15 / Problem Status 0x0 för oem5.inf.
  - Forensikfönster (~8 min): ingen ny CM_PROB_FAILED_DRIVER_ENTRY/ xC0000059 eller SCM 7000; däremot fallback-event med display.inf och  xC00000E5 efter bindförsök.
  - Recovery: PASS (display.inf / BasicDisplay / CM_PROB_NONE).
## 2026-05-07 Forensic Ladder (A6-A10, headless=0, skipHw=1)

- 22:15 CEST - FORENSIC_A6_CHILD_HEAD0
  - Delta: Added only child DDIs (`QueryChildRelations`, `QueryChildStatus`, `QueryDeviceDescriptor`).
  - Result: Event 411 on `oem5.inf` => Problem `0x15`, Status `0x0`.
  - Recovery: PASS (`display.inf` / `BasicDisplay` / `CM_PROB_NONE`).

- 22:17 CEST - FORENSIC_A7_VIDPN_BASE
  - Delta: Added VidPN base DDIs (`IsSupportedVidPn`, `RecommendFunctionalVidPn`, `EnumVidPnCofuncModality`, `CommitVidPn`, `UpdateActiveVidPnPresentPath`, `RecommendMonitorModes`, `QueryVidPnHWCapability`).
  - Result: Event 411 on `oem5.inf` => Problem `0x0`, Status `0xC00000E5`.
  - Recovery: PASS.

- 22:21 CEST - FORENSIC_A8_SCANOUT_VIS
  - Delta: Added `SetVidPnSourceAddress`, `SetVidPnSourceVisibility`, `GetScanLine`.
  - Result: Event 411 on `oem5.inf` => Problem `0x0`, Status `0xC00000E5`.
  - Forensics: recurrent System event 7000 (`Indicates two revision levels are incompatible`) still observed near bind window.
  - Recovery: PASS.

- 22:23 CEST - FORENSIC_A9_CTRLINT_ONLY
  - Delta: Added only `DxgkDdiControlInterrupt` (ISR/DPC remain `NULL`).
  - Result: Event 411 on `oem5.inf` => Problem `0x15`, Status `0x0`.
  - Forensics: System event 7000 revision-incompatible still observed.
  - Recovery: PASS.

- 22:25 CEST - FORENSIC_A10_ALLOC_ONLY
  - Delta: Added `Create/DestroyDevice` + `Create/Open/Close/DestroyAllocation` (still no context/render/submit/fence/ISR/DPC).
  - Result: Event 411 on `oem5.inf` => Problem `0x0`, Status `0xC00000E5`.
  - Recovery: PASS.

- Notes:
  - Every iteration used signed package path and guarded fallback.
  - `0xC0000059` was not re-observed as explicit Problem Status in Kernel-PnP 411 during A6-A10.
  - Failure class alternates between `Problem 0x15/Status 0x0` and `Problem 0x0/Status 0xC00000E5`.
- 22:27 CEST - FORENSIC_A10B_ALLOC_NOCTRL
  - Delta: Same as A10 but `DxgkDdiControlInterrupt=NULL`.
  - Result: Event 411 on `oem5.inf` => Problem `0x15`, Status `0x0`.
  - Recovery: PASS.

- 22:29 CEST - FORENSIC_A11_CTX_ONLY
  - Delta: Added `CreateContext` + `DestroyContext` (no render/present/submit/patch/fence, ISR/DPC still NULL, ControlInterrupt=NULL).
  - Result: Event 411 on `oem5.inf` => Problem `0x0`, Status `0xC00000E5`.
  - Recovery: PASS.
- 22:37 CEST - FORENSIC_A11_POSTREBOOT
  - Delta: Post-reboot validation run with current A11 callback profile.
  - Result: Event 411 on `oem5.inf` => Problem `0x15`, Status `0x0`.
  - Recovery: PASS (`display.inf` / `BasicDisplay` / `CM_PROB_NONE`).
## 2026-05-07 A7 Microstep Forensics (R2, validated push)

- 22:44 CEST - FORENSIC_A6_PASSIVE_BASE
  - Config: strict A6 base + passive Enum/RecommendFunctional patch present, `AMDBC250_A7_MICROSTEP=0`.
  - Result: `Problem 0x0 / Status 0xC00000E5`.
  - Recovery: PASS.

- 22:52 CEST - FORENSIC_A7a_ISSUPPORTED_ONLY_R2
  - Delta: `+ IsSupportedVidPn` only.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 22:53 CEST - FORENSIC_A7b_PLUS_ENUM_R2
  - Delta: `+ EnumVidPnCofuncModality` (passive read-only success).
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 22:54 CEST - FORENSIC_A7c_PLUS_COMMIT_R2
  - Delta: `+ CommitVidPn`.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 22:54 CEST - FORENSIC_A7d_PLUS_RECMON_R2
  - Delta: `+ RecommendMonitorModes`.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 22:55 CEST - FORENSIC_A7e_PLUS_RECFUNC_R2
  - Delta: `+ RecommendFunctionalVidPn` (patched to `STATUS_SUCCESS`).
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 22:56 CEST - FORENSIC_A7f_PLUS_UPDATEPATH_R2
  - Delta: `+ UpdateActiveVidPnPresentPath`.
  - Result: `Problem 0x0 / Status 0xC00000E5` (first reappearance in this ladder).
  - Recovery: PASS.

- 22:57 CEST - FORENSIC_A7g_PLUS_QHWCAP_R2
  - Delta: `+ QueryVidPnHWCapability`.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- Summary:
  - Breakpoint in validated microstep ladder is `A7f (+UpdateActiveVidPnPresentPath)`.
  - `A7b` with passive Enum did **not** introduce `0xC00000E5`.
  - Recent system-window grep: `0xC0000059` count = 0, revision-mismatch phrase count = 0.
## 2026-05-07 A7f Focus Batch (control + behavior probes)

- 23:07 CEST - FORENSIC_A7f1_CTRL_NO_UPDATEPATH
  - Config: A7e profile (`AMDBC250_A7_MICROSTEP=5`), `UpdateActiveVidPnPresentPath` not registered.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 23:08 CEST - FORENSIC_A7f2_UPDATEPATH_NOTSUPPORTED
  - Config: A7f profile (`AMDBC250_A7_MICROSTEP=6`) + `AMDBC250_UPDATEPATH_PROBE_MODE=1` (`STATUS_NOT_SUPPORTED`).
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 23:09 CEST - FORENSIC_A7f3_UPDATEPATH_SUCCESS_LOG
  - Config: A7f profile + `AMDBC250_UPDATEPATH_PROBE_MODE=2` (success + defensive path logging).
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 23:10 CEST - FORENSIC_A7f3_UPDATEPATH_SUCCESS_LOG_REPRO
  - Config: repeat of A7f-3 for reproducibility.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- Focus conclusion:
  - In this controlled batch, `0xC00000E5` did **not** reproduce in A7f variants.
  - `UpdateActiveVidPnPresentPath` behavior (`NULL`, `NOT_SUPPORTED`, or guarded `SUCCESS`) all stayed in `0x15/0x0` class.
## 2026-05-07 StartDevice/QAI Proof Runs (B1-B3)

- 23:28 CEST - B1_SAFEPROFILE_COUNTERS
  - Profile: safe display profile enabled (no allocation/context/render), `headless=0`, `skipHw=1`.
  - Variant: `AMDBC250_QAI_UNKNOWN_NOTSUPPORTED=0` (unknown QAI => zero-success), `AMDBC250_DUMP_QAI_ON_STOPREMOVE=0`.
  - Result: `Problem 0x0 / Status 0xC00000E5`.
  - Recovery: PASS.

- 23:28 CEST - B2_SAFEPROFILE_UNKNOWN_NOTSUPPORTED
  - Same profile.
  - Variant: `AMDBC250_QAI_UNKNOWN_NOTSUPPORTED=1` (unknown QAI => `STATUS_NOT_SUPPORTED`), dump disabled.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 23:29 CEST - B3_SAFEPROFILE_QAI_DUMP20
  - Same profile.
  - Variant: unknown QAI => `STATUS_NOT_SUPPORTED`, dump-on-stop/remove enabled.
  - Result: `Problem 0x0 / Status 0xC00000E5`.
  - Recovery: PASS.

- 23:31 CEST - B2_REPRO_UNKNOWN_NOTSUPPORTED
  - Repeat of B2.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 23:32 CEST - B3_REPRO_QAI_DUMP20
  - Repeat of B3.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- Evidence:
  - `forensic_b1_b3_extract_20260507.txt` contains full iteration summaries.
  - Global callback counters and QAI ring-buffer instrumentation are now compiled into KMD for continued forensics.
- 23:39 CEST - C3_B2SAFE_CONSERV_DRIVERCAPS
  - Profile: B2-safe baseline with strict DriverEntry + safe display profile, `headless=0`, `skipHw=1`, `reportedVramMb=4096`.
  - Change: conservative DRIVERCAPS (`SupportKernelModeCommandBuffer=FALSE`, `NbAsymetricProcessingNodes=0`) + lifecycle/QAI global counter instrumentation enabled.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS (`display.inf` / `BasicDisplay` / `CM_PROB_NONE`).
- 23:42 CEST - C4_FORCE_WDDM13
  - Variant: B2-safe + conservative DRIVERCAPS + forced WDDM caps 1.3.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 23:43 CEST - C5_SEGMENT_V1_ONLY
  - Variant: same as C4 + disable `QUERYSEGMENT2/3` responses (`v1-only`).
  - Result: `Problem 0x0 / Status 0xC00000E5`.
  - Recovery: PASS.

- 23:43 CEST - C6_QSEG3_FORCE_ZERO_PAGING
  - Variant: same as C4 + force `QUERYSEGMENT3` paging buffer size to `0`.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.
## 2026-05-08 QSEG Flag Matrix Start (D1/D2)

- 08:47 CEST - D1_QSEG_APERTURE
  - Variant: C4/C6-safe base + segment flag profile D1 (`CpuVisible=1`, `Aperture=1`, `CacheCoherent=0`, `PopulatedFromSystemMemory=1`).
  - Result: `Problem 0x0 / Status 0xC00000E5`.
  - Recovery: PASS.

- 08:48 CEST - D2_QSEG_APERTURE_COHERENT
  - Variant: same base + segment flag profile D2 UMA/aperture coherent (`CpuVisible=1`, `Aperture=1`, `CacheCoherent=1`, `PopulatedFromSystemMemory=1`).
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- 08:49 CEST - D2_REPRO_QSEG_APERTURE_COHERENT
  - Variant: repeat D2 for stability.
  - Result: `Problem 0x15 / Status 0x0`.
  - Recovery: PASS.

- Signal:
  - Enabling aperture without coherence (D1) is unstable (`0xE5`).
  - Adding coherence in UMA aperture profile (D2) shifts back to cleaner `0x15/0` and reproduces.

## 2026-05-08 Best D2+8192 Reboot Bind

- 16:42 CEST - BEST_D2_8192_ACTIVE_REBOOT
  - Change: promoted Linux-aligned D2 baseline into the active package: `REPORTED_VRAM_MB_OVERRIDE=8192`, `FORCE_WDDM_CAPS_LEVEL=13`, `CpuVisible=1`, `Aperture=1`, `CacheCoherent=1`, `PopulatedFromSystemMemory=1`, single segment, safe display profile.
  - Build: PASS on BC-250. KMD/UMD built; KMD explicitly linked to `build\Release\x64\package\amdbc250kmd.sys` (39808 bytes); `inf2cat`, SYS signing, CAT signing, and `signtool verify /pa` all passed.
  - Install: PASS. `pnputil /add-driver ... /install` returned `3010` and selected `oem5.inf` as best-ranked/installed. Device was `CM_PROB_NEED_RESTART` before reboot.
  - Reboot: PASS. SSH returned after reboot.
  - Result after reboot: FAIL, `CM_PROB_FAILED_DRIVER_ENTRY`, `Problem Code 37`, `Problem Status 0xC0000059`, active service `amdbc250kmd`, driver INF `oem5.inf`. Kernel-PnP Event 219: `\Driver\amdbc250kmd failed to load`.
  - Recovery: PASS. Deleted `oem5.inf` with `/uninstall /force`, rescanned/restarted device, restored `Microsoft Basic Display Adapter` / `display.inf` / `Started`.
  - Evidence on target: `C:\Dev\BC250-windowsDriverTest\best_d2_8192_link_package_20260508_164213.log`, `C:\Dev\BC250-windowsDriverTest\best_d2_8192_install_reboot_20260508_164248.log`, `C:\Dev\BC250-windowsDriverTest\best_d2_8192_postboot_rollback_20260508_*.log`.

## 2026-05-08 K0 Strict DriverEntry No-Reboot

- 17:10 CEST - K0_STRICT_DRIVERENTRY_REVALIDATE_NO_REBOOT
  - User constraint: no reboot.
  - Change: added unique binary marker `K0_STRICT_DRIVERENTRY_REVALIDATE_20260508_1648`; set `AMDBC250_K0_STRICT_DRIVERENTRY=1`; kept `REPORTED_VRAM_MB_OVERRIDE=8192` and true D2 `UMA_FLAGS_PROFILE=2`.
  - DriverEntry DDI table: strict minset only: lifecycle, `DispatchIoRequest`, `SetPowerState`, `Unload`, `QueryAdapterInfo`. Child/VidPN/scanout/render/allocation/scheduler/ISR/DPC disabled for this run.
  - Build gate: PASS after removing unsupported `__declspec(allocate(".rdata"))` marker attribute. Clean KMD build, UMD build, explicit link, `inf2cat`, SYS sign, CAT sign, `signtool verify /pa` all passed.
  - Binary gate: PASS. Marker found in packaged `.sys`; SHA256 `4F905374692E88334E34A4CE1288D21D7D6A5049AEC1393A6071B259C800A7AF`; packaged SYS size 40320 bytes.
  - Install: `pnputil /add-driver ... /install` returned `3010`; package published as `oem2.inf`; no reboot performed.
  - Runtime result: `CM_PROB_NEED_RESTART` after no-reboot restart attempt; `pnputil /restart-device` reported pending system reboot from previous operation. Event 219 still appeared for `\Driver\amdbc250kmd failed to load` at install time, but no reboot was allowed so this run cannot fully classify post-boot DriverEntry status.
  - Recovery: PASS. Deleted `oem2.inf`, rescanned/restarted device, restored `Microsoft Basic Display Adapter` / `display.inf` / `Started`.
  - Evidence on target: `C:\Dev\BC250-windowsDriverTest\k0_strict_driverentry_noreboot_20260508_171046.log`.

## 2026-05-08 K1 Service-Load No-Reboot

- 19:53 CEST - K1_VERIFIED_SYS_SERVICE_LOAD
  - User constraint: no reboot.
  - Input binary: package `amdbc250kmd.sys` with build marker `K0_STRICT_DRIVERENTRY_REVALIDATE_20260508_1648`.
  - Hash gate: PASS. Package hash = destination hash = `14F07A1544B60B31F3CA1955754738F9BE5AB539728F021EFF42B85A75717F92`.
  - Method: copied `.sys` to `System32\\drivers\\amdbc250kmd_k1.sys`, created temporary kernel service `amdbc250kmd_k1`, attempted `sc start`.
  - Result: FAIL with `StartService FAILED 1306` (`ERROR_REVISION_MISMATCH`: two revision levels are incompatible).
  - SCM evidence: Event 7000 logged same error for service `BC250 K1 Service Load`.
  - Interpretation: failure reproduces at pure kernel image/service-load level (pre-PnP/VidPN path), so current blocker is still interface/ABI/loader contract mismatch class.
  - Recovery: PASS. Temporary service deleted and temp driver file removed; baseline display adapter remains active.
  - Evidence on target: `C:\\Dev\\BC250-windowsDriverTest\\k1_service_load_20260508_195311.log`.

## 2026-05-08 L0/L1 Kernel Contract

- 20:00 CEST - L0_L1_KERNEL_CONTRACT_NO_REBOOT
  - User constraint: no reboot.
  - L0 PE/Import artifacts generated on target for active package sys:
    - `C:\\Dev\\BC250-windowsDriverTest\\L0_headers.txt`
    - `C:\\Dev\\BC250-windowsDriverTest\\L0_imports.txt`
    - `C:\\Dev\\BC250-windowsDriverTest\\L0_loadconfig.txt`
    - `C:\\Dev\\BC250-windowsDriverTest\\L0_signtool_verify.txt`
  - L1 minimal kernel service-load probe (header-free stub, entry `MyEntry`) built/signed/deployed no-reboot.
  - L1 build/link/sign: PASS.
  - L1 service start: PASS (`sc start bc250hello` exit 0, service state RUNNING).
  - L1 hash: `AF7748B3F37CAFA542484E5BA4ACF296731314B17C56F411D354EBA39E3834FD`.
  - Interpretation: host/toolchain/service-loader path is valid; `ERROR_REVISION_MISMATCH (1306)` is specific to current BC250 KMD image/contract, not generic kernel-service loading.
  - Cleanup: PASS (temporary service removed; temporary sys removed).
  - Evidence on target: `C:\\Dev\\BC250-windowsDriverTest\\l0_l1_kernel_contract_20260508_200057.log`.

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

## 2026-05-08 21:39 P0_N9C_DXGK_MIN_PNP_BIND_HASHED (no reboot)
- Harness: `P0-N9C-PnpBind-Hashed-NoReboot.ps1` on `192.168.50.189`.
- Goal: verify N9C via correct PnP-bind context (not manual `sc start`) with strict hash gate.
- Package path: `C:\Dev\BC250-windowsDriverTest\p0_pkg_20260508_213923`.
- Hash gate:
  - `A` source (`N9C_ENTRYONLY_DXGK_MIN.sys`) = `C0324F5DB13EB58F9B4BC89147E8EDDF53EDDEB35AEA1B600CA491CB43CA064E`
  - `B` staged package `amdbc250kmd.sys` = same hash
  - `C` DriverStore `...\amdbc250.inf_amd64_76fb8cca894921c9\amdbc250kmd.sys` = same hash
  - `A_EQ_B=True`, `A_EQ_C=True`, `B_EQ_C=True`
- Install result:
  - `pnputil /add-driver ... /install` published `oem2.inf`, exit `3010` (reboot required flag).
  - `Kernel-PnP 219`: `\Driver\amdbc250kmd failed to load` for `PCI\VEN_1002&DEV_13FE...`.
  - `setupapi.dev.log`: `CM_PROB_FAILED_DRIVER_ENTRY (0x25), problem status 0xC0000059`.
  - Device state after bind: `AMD BC-250 Graphics Adapter`, service `amdbc250kmd`, `ProblemCode=14`, `ProblemStatus=0x00000000`.
- Interpretation:
  - `DxgkInitialize` failure reproduces even in PnP display-start context with verified fresh artifact.
  - This rules out `sc start`-only-context as sole cause for N9C failure.

## 2026-05-08 21:45 P1_N9D_N9E_N9F_PNP_MATRIX (no reboot)
- Build stage: `N9DEF-BuildOnly-NoReboot.ps1` generated fresh artifacts:
  - `N9D_DXGK_EMPTY.sys` A hash `4DA3C054BDF89498EE4BE7063FC05282A0BA4D351CD14D79E6FF61761EAFDB54`
  - `N9E_DXGK_MINCALLBACK.sys` A hash `596CECFD7B82A1780BA8830C1CD1A54C6030BA9DCC885CC22F52FC2F2222603E`
  - `N9F_DOD_MIN.sys` A hash `AE21D1ED44D7BC8D2C8011AE5C055FD9F839FA03846DCF54D67803F61676D670`
- Harness update: `P0-N9C-PnpBind-Hashed-NoReboot.ps1` patched to:
  - force unique INF `DriverVer` per run (prevents â€œalready up-to-dateâ€ bypass)
  - fix device instance match pattern
- First matrix attempt (21:44) was invalid for verdict:
  - `pnputil` returned `259` (`already exists/up-to-date`), DriverStore hash stayed on previous N9C payload.
- Corrected matrix (21:45) with forced `DriverVer` produced real installs:
  - N9D -> `oem9.inf`, `PNPUTIL_EXIT=0`, `ProblemCode=37`, `ProblemStatus=0xC0000059`
  - N9E -> `oem10.inf`, `PNPUTIL_EXIT=0`, `ProblemCode=37`, `ProblemStatus=0xC0000059`
  - N9F -> `oem11.inf`, `PNPUTIL_EXIT=0`, `ProblemCode=37`, `ProblemStatus=0xC0000059`
- Hash gate evidence for each corrected run:
  - staged/signed package sys `B` equals active DriverStore sys `C` (`B_EQ_C=True`)
  - `A_EQ_C` is false after signing (expected; signature/timestamp mutates bytes)
- Event evidence:
  - Kernel-PnP Event 219 on each run: `\Driver\amdbc250kmd failed to load` for `PCI\VEN_1002&DEV_13FE...`
- Conclusion:
  - In proper PnP context with fresh artifacts and rank-forced installs, all N9D/N9E/N9F variants fail identically at DriverEntry with `0xC0000059`.
  - `DxgkInitialize` path is still the failure boundary; callback breadth and DOD entry path did not change outcome.

## 2026-05-08 21:51 N9R_REGISTRY_BREADCRUMB_PNP (no reboot)
- Built `N9R_DXGK_BREADCRUMB.sys` (`n9r_build_20260508_215110`) and installed via PnP hash-gated harness.
- Install proof:
  - `pnputil` published `oem12.inf`, installed on BC-250 device.
  - DriverStore active sys hash matched signed package (`B_EQ_C=True`).
- Runtime result unchanged:
  - `ProblemCode=37 (CM_PROB_FAILED_DRIVER_ENTRY)`
  - `ProblemStatus=0xC0000059`
  - Kernel-PnP Event 219 (`\Driver\amdbc250kmd failed to load`).
- Registry breadcrumbs (from `HKLM\SYSTEM\CurrentControlSet\Services\amdbc250kmd\Parameters`):
  - `Bc250ReachedDriverEntry = 1`
  - `Bc250InitVersion = 49156 (0x0000C004)`
  - `Bc250InitSize = 1232`
  - `Bc250CallbackCount = 8`
  - `Bc250Phase = 2`
  - `Bc250DxgkStatus = 3221225561 (0xC0000059)`
- Interpretation:
  - Driver reaches `DriverEntry`, calls `DxgkInitialize`, returns with `0xC0000059` explicitly.
  - Confirms failure is Dxgk initialization ABI/contract boundary (not post-init runtime, not logging ambiguity).

## 2026-05-08 21:52 Q0_KMDOD_SAMPLE_FETCH_AND_BUILD_ATTEMPT
- Fetched Microsoft sample repo (sparse): `C:\Dev\windows-driver-samples\video\KMDOD`.
- Attempted build of `Sample\SampleDisplay.vcxproj` with local MSBuild: failed compile (`ntddk.h` not found).
- Additional attempts:
  - Set `DDK_INC_PATH/SDK_INC_PATH/DDK_LIB_PATH` env vars explicitly.
  - Patched `SampleDisplay.vcxproj` include/lib macro strings.
  - Result unchanged: sample still resolves includes via external property path and fails before codegen.
- Current Q0 status:
  - Sample source is present and ready.
  - Build environment/property import mismatch blocks straight sample compile in current shell.
- Impact:
  - Does not change N9R proof; `DxgkInitialize` still returns `0xC0000059` on BC-250 PnP bind.

## 2026-05-08 22:25 N9R_VERSION_PIN_MATRIX (no reboot)
- Build set (`n9rver_build_20260508_221619`):
  - `R13_VER_0x4002.sys`
  - `R20_VER_0x5023.sys`
  - `R21_VER_0x6003.sys`
  - `R27_VER_0xC004.sys`
- Common setup:
  - Same 8 callbacks (`mask=0xFF`), same breadcrumb logic.
  - PnP hash-gated per run with unique INF `DriverVer` (fresh `oem*.inf`).
  - DriverStore payload matched signed package each run (`B_EQ_C=True`).
- Results:
  - `R13 (init.Version=0x4002)` -> `PROBLEM_STATUS=0xC0000059`, breadcrumb `Bc250DxgkStatus=0xC0000059`.
  - `R20 (init.Version=0x5023)` -> `PROBLEM_STATUS=0xC0000059`, breadcrumb `Bc250DxgkStatus=0xC0000059`.
  - `R21 (init.Version=0x6003)` -> `PROBLEM_STATUS=0xC0000059`, breadcrumb `Bc250DxgkStatus=0xC0000059`.
  - `R27 (init.Version=0xC004)` -> `PROBLEM_STATUS=0xC0000059`, breadcrumb `Bc250DxgkStatus=0xC0000059`.
- Additional breadcrumb constants (all runs):
  - `Bc250DxgkInterfaceVersionMacro=0x0000C004`
  - `Bc250BuildNtddi=0x0A000000`
  - `Bc250BuildWin32Winnt=0x00000A00`
  - `Bc250DriverInitDataSize=1232`
- Interpretation:
  - Manual version pinning alone does not bypass `DxgkInitialize` revision mismatch.
  - Root issue is not just interface-version literal; likely deeper DXGK contract/ABI expectation mismatch with current minimal WDM-linked shape.

## 2026-05-08 22:32 S_CALLBACK_SHAPE_MATRIX (no reboot, hash-gated)
- Build set: `n9s_shape_build_20260508_223139`
  - `S0_EMPTY_V4002`
  - `S1_LIFECYCLE_V4002`
  - `S2_LIFE_PWR_IO_V4002`
  - `S3_PLUS_QAI_V4002`
  - `S4_DODLIKE_V4002`
  - `S5_FULLDISP_V4002`
  - `S3_PLUS_QAI_VC004`
  - `S4_DODLIKE_VC004`
- Harness: `P0-N9C-PnpBind-Hashed-NoReboot.ps1` (patched to log breadcrumb params including shape/struct kind/first-last offsets).

### Results
- S0 (`shape=0`, `struct=DRIVER_INITIALIZATION_DATA`, `version=0x4002`, `count=0`, `mask=0x00000000`) -> `0xC0000059`
- S1 (`shape=1`, lifecycle only, `count=4`, `mask=0x0000000F`) -> `0xC0000059`
- S2 (`shape=2`, +Power/Dispatch/Unload, `count=7`, `mask=0x0000007F`) -> `0xC0000059`
- S3 (`shape=3`, +QAI, `count=8`, `mask=0x000000FF`) -> `0xC0000059`
- S4 (`shape=4`, KMDOD-like via `KMDDOD_INITIALIZATION_DATA`, `count=22`, `mask=0x003FFFFF`) -> `0xC0000059`
- S5 (`shape=5`, extended display callback set in `DRIVER_INITIALIZATION_DATA`, `count=22`, `mask=0x003FFFFF`) -> `0xC0000059`
- S3 control @ `0xC004` -> `0xC0000059`
- S4 control @ `0xC004` -> `0xC0000059`

### Integrity checks
- All runs had `B_EQ_C=True` (signed package payload equals active DriverStore payload).
- All runs had `Bc250ReachedDriverEntry=1`, `Bc250Phase=2`, and `Bc250DxgkStatus=0xC0000059`.
- Kernel-PnP Event 219 emitted each run (`\Driver\amdbc250kmd failed to load`).

### Interpretation
- Callback-shape broadening/minimization does not change failure class.
- Version pinning + shape variation + struct kind (`DRIVER_INITIALIZATION_DATA` vs `KMDDOD_INITIALIZATION_DATA`) all still fail at `DxgkInitialize` with `STATUS_REVISION_MISMATCH`.
- Remaining highest-value branch is build/environment ABI parity: project property chain, include/lib provenance, and direct project-shape cross-build against KMDOD baseline.

## 2026-05-09 12:04 T_ABI_LAYOUT_DUMP + P0 re-run (no reboot)
- Harness patch:
  - `P0-N9C-PnpBind-Hashed-NoReboot.ps1` now clears `HKLM\SYSTEM\CCS\Services\<service>\Parameters` before install.
  - Harness now logs all `Bc250*` and `Abi*` values, not only fixed key list.
- Result:
  - `PNPUTIL_EXIT=0`, `ProblemCode=37`, `ProblemStatus=0xC0000059`, `SERVICE=amdbc250kmd`.
  - `B_EQ_C=True` (signed package equals active DriverStore payload).
  - `A_EQ_C=False` (expected after sign/timestamp mutation).
- Captured ABI breadcrumbs:
  - `AbiSize_DRIVER_INITIALIZATION_DATA = 0x4D0` (1232)
  - `AbiSize_KMDDOD_INITIALIZATION_DATA = 0x150` (336)
  - `AbiOff_DRV_AddDevice = 0x08`, `AbiOff_DRV_StartDevice = 0x10`, `AbiOff_DRV_QueryAdapterInfo = 0x88`
  - `AbiOff_DRV_SetVidPnSourceAddress = 0x140`, `AbiOff_DRV_ControlInterrupt = 0x180`, `AbiOff_DRV_QueryVidPnHWCapability = 0x230`
  - `AbiOff_DOD_AddDevice = 0x08`, `AbiOff_DOD_StartDevice = 0x10`, `AbiOff_DOD_QueryAdapterInfo = 0x88`
  - `AbiOff_DOD_PresentDisplayOnly = 0x100`, `AbiOff_DOD_ControlInterrupt = 0x128`, `AbiOff_DOD_QueryVidPnHWCapability = 0xF8`
  - `Bc250BuildNtddi = 0x0A000000`, `Bc250BuildWin32Winnt = 0x00000A00`, `Bc250DxgkInterfaceVersionMacro = 0x0000C004`
- Verdict:
  - Failure remains at `DxgkInitialize -> 0xC0000059`.

## 2026-05-09 12:07 Q1_SAMPLE_SOURCE_ON_BC250_BUILD_SURFACE (KMDOD project attempt)
- Action:
  - Built `C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj` on BC-250 host.
- Result:
  - Build failed before link.
  - First fail: `ntddk.h` not found when sample was patched to `10.0.26100.0` include surface.
  - Validation: `...\Include\10.0.26100.0\km\ntddk.h` is missing on target, while `10.0.22000.0` and `10.0.19041.0` contain `ntddk.h`.
  - Repoint attempt to `10.0.22000.0` still fails with `ntdef.h: #error "No Target Architecture"` due mixed sample property surface.
- Verdict:
  - Sample-crossbuild branch is currently blocked by KMDOD project environment/property chain mismatch on target.

## 2026-05-09 12:19 Q1 normalisering + sample-kod testad i samma P0-surface
- KMDOD project chain normaliserad till en konsekvent x64/WDK yta (`10.0.19041.0`), med `_AMD64_` defs och explicita include/lib path.
- `SampleDisplay.vcxproj` kompilerar nu rent (warnings only) på target i Release|x64.
- VS-projektet producerade inte `.sys` direkt (TargetPath/TargetExt-surface avvek), så sample-objekten länkades manuellt till:
  - `Q1_SAMPLEDISPLAY_MANUAL.sys`
  - Link: `/DRIVER:WDM /ENTRY:DriverEntry /SUBSYSTEM:NATIVE` + km libs (`ntoskrnl/hal/wdmsec/displib/wdm/BufferOverflowFastFailK`).
- P0 hash-gated bind kördes med sample-manual sys:
  - `B_EQ_C=True`
  - Device outcome: `ProblemCode=31 (CM_PROB_FAILED_ADD)`
  - `ProblemStatus=0xC0000017`
  - Service path: `amdbc250kmd`
  - `Parameters` saknas (`PARAM_PATH_MISSING`), dvs inga BC250-breadcrumbs från denna sample-binary.
- SetupAPI bevis (12:19:25):
  - `Device ... not started: Device has problem: 0x1f (CM_PROB_FAILED_ADD), problem status: 0xc0000017`.

### Interpretation
- Kritisk differens mot N9R/N9S-linjen:
  - BC250-minimal DXGK probes: `0xC0000059` (DriverEntry/DxgkInitialize revision mismatch)
  - KMDOD-sample-kod (samma P0 installsurface): `0xC0000017` / `CM_PROB_FAILED_ADD`
- Detta talar för att `0xC0000059` inte är ett helt globalt OS-block i installkedjan, utan starkt kopplat till BC250-initkontrakt/build-shape.
- Ny huvudfråga blir vad i BC250 init-pathen som triggar `0xC0000059` medan sample-pathen passerar den grinden men faller senare på `FAILED_ADD`.

## 2026-05-09 13:24 Q2C callback-shape matrix (sample DOD path, no reboot)
Using `DxgkInitializeDisplayOnlyDriver` + `KMDDOD_INITIALIZATION_DATA (0x150)` + sample code surface:

- `Q2C_FULL28` (28 callbacks):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017` (`CM_PROB_FAILED_ADD`)

- `Q2C_MID14` (14 callbacks):
  - `SampleDxgkStatus=0xC0000059`
  - Device: `ProblemCode=37`, `ProblemStatus=0xC0000059`

- `Q2C_MIN8` (8 callbacks):
  - `SampleDxgkStatus=0xC0000059`
  - Device: `ProblemCode=37`, `ProblemStatus=0xC0000059`

Common integrity:
- `B_EQ_C=True` in all three runs.
- `SampleInitApi=2`, `SampleInitVersion=0xC004`, `SampleInitSize=0x150`, `SampleReachedDriverEntry=1`.

Interpretation:
- Regression boundary is callback-set completeness in DOD init path.
- Full sample callback surface passes init (`Status=0`) and fails later (`0xC0000017`).
- Reducing callback set to 14 or 8 reintroduces init-time `0xC0000059`.

## 2026-05-09 13:29 Q2C prefix bisect rerun (sample DOD path, no reboot)
Log source: `E:\world view\BC250-windowsDriverTest\q2c_prefix_bisect_rerun_20260509_$(Get-Date -Format HHmmss).log`

Using sample callback order with `DxgkInitializeDisplayOnlyDriver` and hash-gated P0 bind:

- `Q2C_PFX17` (callbacks 1-17):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `Q2C_PFX19` (callbacks 1-19):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `Q2C_PFX20` (callbacks 1-20):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `Q2C_PFX21` (callbacks 1-21):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

Interpretation:
- Prefix sets at 17+ callbacks now all pass Dxgk DOD init (`SampleDxgkStatus=0`).
- Earlier `MID14` failure (`0xC0000059`) is therefore callback-composition dependent, not only callback-count dependent.
- New minimal known-good init prefix boundary is currently `1-17` in sample order.

## 2026-05-09 13:32 Q2C prefix threshold (14-17) rerun
Log source: `E:\world view\BC250-windowsDriverTest\q2c_prefix_threshold_rerun_20260509_132849.log`

Using strict sample callback prefix order:

- `Q2C_PFX14` (callbacks 1-14):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `Q2C_PFX15` (callbacks 1-15):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `Q2C_PFX16` (callbacks 1-16):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `Q2C_PFX17` (callbacks 1-17):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

Interpretation:
- `MID14` failure (`0xC0000059`) is composition-driven, not count-driven.
- A 14-callback set can pass init when it matches sample prefix composition.
- Strong suspect: callbacks present in prefix14 but absent in MID14 (`ResetDevice`, `InterruptRoutine`, `DpcRoutine`) are part of the accepted DOD init contract in this environment.
- Next isolation test should add these three callbacks to MID14 while keeping the rest unchanged.

## 2026-05-09 13:36 M14R/M14I/M14RID composition test (no reboot)
Log source: `E:\world view\BC250-windowsDriverTest\q2c_m14rid_run_20260509_133337.log`

Goal: isolate whether `MID14` failure (`0xC0000059`) is recovered by adding `ResetDevice`, `InterruptRoutine`, `DpcRoutine`.

- `M14R` (`MID14 + ResetDevice`, 15 callbacks):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

- `M14I` (`MID14 + InterruptRoutine + DpcRoutine`, 16 callbacks):
  - `SampleDxgkStatus=0xC0000059`
  - Device: `ProblemCode=37`, `ProblemStatus=0xC0000059`
  - `B_EQ_C=True`

- `M14RID` (`MID14 + ResetDevice + InterruptRoutine + DpcRoutine`, 17 callbacks):
  - `SampleDxgkStatus=0x00000000`
  - Device: `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `B_EQ_C=True`

Interpretation:
- `ResetDevice` is the decisive recovery callback in this branch.
- `InterruptRoutine + DpcRoutine` without `ResetDevice` do not recover init (still `0xC0000059`).
- Working minimal family now includes sample-prefix-compatible sets and `MID14 + ResetDevice`.

## 2026-05-09 13:41-13:43 O-series Add/Start forensic batch (no reboot)
Scripts/logs:
- `O-Series-AddStart-Breadcrumb-Run.ps1`
- `o_series_run_20260509_133912.log` (O1 + O2 compile-fail branch)
- `o_series_run2_20260509_133959.log` (O2..O5)

Baseline used:
- DOD init path (`DxgkInitializeDisplayOnlyDriver`) with MID14+Reset callback composition.
- Added registry breadcrumbs in callbacks: `SampleO_AddEnter`, `SampleO_AddStatus`, and Start markers.

Profiles and outcomes:
- `O1` (`Add=normal`, `Start=orig`):
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `SampleO_AddEnter=1`, `SampleO_AddStatus=0xC0000017`

- `O2` (`Add=nomem`, `Start=orig`):
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `SampleO_AddEnter=1`, `SampleO_AddStatus=0xC0000017`

- `O3` (`Add=normal`, `Start=1/1 forced`):
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `SampleO_AddEnter=1`, `SampleO_AddStatus=0xC0000017`

- `O4` (`Add=normal`, `Start=0/0 forced`):
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `SampleO_AddEnter=1`, `SampleO_AddStatus=0xC0000017`

- `O5` (`Add=normal`, `Start=STATUS_UNSUCCESSFUL forced`):
  - `SampleDxgkStatus=0x00000000`
  - `ProblemCode=31`, `ProblemStatus=0xC0000017`
  - `SampleO_AddEnter=1`, `SampleO_AddStatus=0xC0000017`

Integrity:
- `B_EQ_C=True` in all completed runs.

Interpretation:
- All tested branches fail at/inside `AddDevice` with `STATUS_NO_MEMORY (0xC0000017)` *before* any StartDevice-path differentiation.
- Start behavior toggles (`orig`, `1/1`, `0/0`, forced fail) are currently non-influential because execution does not reach StartDevice in these runs.
- Current primary blocker has moved from init-shape to AddDevice allocation/constructor path.

## 2026-05-09 13:48 P-series AddDevice dummy-context isolation (no reboot)
Script/log:
- `P-Series-DummyCtx-Run.ps1`
- `p_series_run_20260509_134527.log`

Design:
- Replaced `BddDdiAddDevice` with minimal dummy devctx allocation (`ExAllocatePoolWithTag`, tag `D52B`) and explicit breadcrumbs.
- Replaced `BddDdiRemoveDevice` to free dummy context.
- `StartDevice` varied across profiles to isolate post-add behavior.
- Callback surface kept at MID14+Reset-compatible DOD init set.

Profiles/results:
- `P1` (`Start=STATUS_UNSUCCESSFUL`):
  - `SampleDxgkStatus=0x00000000`
  - `SampleO_AddStatus=0x00000000` (Add success)
  - `SampleO_StartEnter=1`, `SampleO_StartStatus=0xC0000001`
  - Device: `ProblemCode=43`, `ProblemStatus=0x00000000`

- `P2` (`Start=SUCCESS`, views/children=`1/1`):
  - `SampleDxgkStatus=0x00000000`
  - `SampleO_AddStatus=0x00000000`
  - `SampleO_StartStatus=0x00000000`, `StartViews=1`, `StartChildren=1`
  - Device: `ProblemCode=43`, `ProblemStatus=0x00000000`

- `P3` (`Start=SUCCESS`, views/children=`0/0`):
  - `SampleDxgkStatus=0x00000000`
  - `SampleO_AddStatus=0x00000000`
  - `SampleO_StartStatus=0x00000000`, `StartViews=0`, `StartChildren=0`
  - Device: `ProblemCode=43`, `ProblemStatus=0x00000000`

Common integrity:
- `B_EQ_C=True` on all P runs.
- `AddIrql=0`, `StartIrql=0` in all P runs.
- `RemoveEnter=1` seen on all runs.

Interpretation:
- Prior `0xC0000017` blocker is tied to sample `BASIC_DISPLAY_DRIVER` constructor path, not generic AddDevice allocation in this environment.
- With dummy context, driver crosses Add/Start and reaches a new stable class: `Code 43`.
- New blocker is now post-start/runtime-capability contract, not init nor AddDevice allocation.
