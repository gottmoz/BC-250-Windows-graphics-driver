# BC-250 Windows Driver Knowledge Base (2026-04-30)

## 1) Executive Summary
- Target device: `PCI\VEN_1002&DEV_13FE&SUBSYS_00001022`
- Stable baseline on BC-250 today: `display.inf` + `BasicDisplay` + `CM_PROB_NONE`
- Key blocker found in latest forced Radeon attempt:
  - SetupAPI shows patched Radeon package path as **not digitally signed** during forced install context.
  - Evidence line: `Signer Score - Not digitally signed` with high rank (`0x80cf0000`) in SetupAPI flow.
- Practical implication:
  - Even when IDs are added, selection/start can still fail due to signature/rank/policy and section-decoration gating.

## 2) Current Proven Facts (Local Runs)
- Multiple no-reboot guarded loops were completed safely.
- Custom BC250 test KMD package can install/stage/sign/start service, but runtime falls back and/or ends at Code 43 in experimental paths.
- Radeon `u0397406.inf` path was repeatedly staged but not selected as active display driver for the BC-250 instance.
- `devcon /f install` against patched Radeon INF created explicit SetupAPI evidence that signature trust/rank is a gating factor.

## 3) Critical Evidence Patterns to Remember
- When Windows selects Basic Display path for BC-250 instance:
  - `Driver Name: display.inf`
  - `Driver Rank: 00FB2008`
  - `Signer Score: INBOX`
- Forced Radeon install evidence (important):
  - `Rank - 0x80cf0000`
  - `Signer Score - Not digitally signed`
- For previous custom test-driver attempts:
  - `CM_PROB_FAILED_POST_START` (Code 43)
  - Repeated fallback to `display.inf`

## 4) BC-250 IDs and Variants (Consolidated)
From BC-250 community repos/docs:
- `PCI\VEN_1002&DEV_13FE`
- `PCI\VEN_1002&DEV_143F`
- `PCI\VEN_1002&DEV_13DB`
- `PCI\VEN_1002&DEV_13F9`
- `PCI\VEN_1002&DEV_13FA`
- `PCI\VEN_1002&DEV_13FB`
- `PCI\VEN_1002&DEV_13FC`

## 5) What We Learned About Radeon INF Path
- ID injection must be in the **active OS-decorated model section**.
- Wrong section or malformed ID syntax makes changes effectively no-op.
- Editing INF invalidates catalog trust unless package is rebuilt/re-signed in a way the target policy accepts.
- `pnputil /add-driver ... /install` stages package but does not guarantee active bind if rank/trust loses.

## 6) Microsoft Driver Model & Diagnostics (Most Relevant)
### Problem codes
- Code 31: `CM_PROB_FAILED_ADD`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-add
- Code 43: `CM_PROB_FAILED_POST_START`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-post-start

### WDDM startup contracts
- `DXGKDDI_START_DEVICE`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/dispmprt/nc-dispmprt-dxgkddi_start_device
- `DXGK_START_INFO`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/dispmprt/ns-dispmprt-_dxgk_start_info
- WDDM PnP cases
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/display/plug-and-play--pnp--start-and-stop-cases

### QueryAdapterInfo requirements
- `DXGKDDI_QUERYADAPTERINFO`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmddi/nc-d3dkmddi-dxgkddi_queryadapterinfo
- `DXGKARG_QUERYADAPTERINFO`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmddi/ns-d3dkmddi-_dxgkarg_queryadapterinfo
- `DXGK_QUERYADAPTERINFOTYPE`
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmddi/ne-d3dkmddi-_dxgk_queryadapterinfotype

### Ranking/selection and logs
- Driver selection overview
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/overview-of-the-driver-selection-process
- Driver rank details
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/how-windows-ranks-driver-packages
- Feature score
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-featurescore-directive
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/display/setting-the-driver-feature-score
- SetupAPI rank interpretation
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/driver-rank-information-in-the-setupapi-log
- SetupAPI logs/troubleshooting
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/setupapi-device-installation-log-entries
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/setupapi-text-logs
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/troubleshooting-device-and-driver-installations

## 7) AMD Package Structure Guidance (WT6A_INF)
- INF Manufacturer/Models sections drive match and chosen install section.
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-manufacturer-section
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-models-section
- DDInstall dependency correctness matters (`Include/Needs`, `CopyFiles`, `.Services`, `AddService`).
  - https://learn.microsoft.com/th-th/windows-hardware/drivers/install/inf-ddinstall-section
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-copyfiles-directive
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-addservice-directive
- Catalog/signature handling:
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/catalog-files
  - https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-version-section

## 8) BC-250 Community & Project Sources
- ZEROAESQUERDA test-driver project:
  - https://github.com/ZEROAESQUERDA/BC250-windowsDriverTest
- Related issue thread:
  - https://github.com/ZEROAESQUERDA/BC250-windowsDriverTest/issues/1
- Keshas reference repo:
  - https://github.com/Keshas-dev/AMD-bc-250-win
- mothenjoyer69 BC250 docs:
  - https://github.com/mothenjoyer69/bc250-documentation
- elektricm BC250 docs:
  - https://elektricm.github.io/amd-bc250-docs/
  - https://elektricm.github.io/amd-bc250-docs/troubleshooting/display/

## 9) PS5/Oberon Context Sources Used
- PS Dev Wiki root:
  - https://www.psdevwiki.com/ps5/
- Useful context pages:
  - GPU/Hardware/Memory/PUP/Build Strings/Devices (navigated via root)

## 10) Practical ?Next Attempt? Matrix
### Attempt A (Radeon path, strict trust)
- Create fresh INF package clone with unique name and correct ID insertion in active decorations.
- Rebuild CAT and sign with cert chain trusted on target.
- Validate in SetupAPI:
  - selected INF file name
  - selected section
  - rank and signer score
  - service add lines for AMD display stack

### Attempt B (Radeon path, exact applicability)
- Insert BC-250 IDs in every applicable AMD `NTamd64.10.0.*` decorated model section used by this package family.
- Keep mapping to valid existing `ati2mtag_*` section for Navi10-like path.

### Attempt C (Custom BC250 test driver path)
- Continue startup contract hardening in KMD (`StartDevice`, `QueryAdapterInfo`, child/source semantics) with fast guarded loop and strict rollback.

## 11) Minimal Rehydrate Checklist (when context window resets)
1. Confirm current target state:
- `Get-PnpDevice -Class Display -PresentOnly`
- `pnputil /enum-devices /instanceid <BC250_INSTANCE> /drivers`
2. Read this document sections 1, 3, 6, 10.
3. Remember key observed blocker in latest Radeon forced run:
- `Signer Score - Not digitally signed` for forced BC-250 install path.
4. Use SetupAPI evidence as ground truth for each new attempt.

## 12) Local Artifacts in This Workspace
- Progress log: `PROGRESS.md`
- Iteration log matrix: `TEST_MATRIX.md`
- BC250 source/test harness: `shared/`, `Run-GuardedDriverTest.ps1`, `live-only-bc250-cycle.ps1`
- PS5 parsing tools/output:
  - `tools/parse_ps5_pup.py`
  - `tools/parse_ps5_decrypted_pup.py`
  - `ps5_pup_analysis/`
  - `ps5_pup_dec_analysis/`

## 13) Complete Test Index (Do-Not-Repeat Reference)
- Canonical detailed logs: `TEST_MATRIX.md`
- Rule: before any new run, check this index and choose a new variable (single-change discipline).

### Executed Test IDs
- ## T-021 - 2026-04-29 17:59 CEST - Minimal VidPN mode-set implementation
- ## T-022 - 2026-04-29 18:01 CEST - Forced post-bind pnputil restart
- ## T-023 - 2026-04-29 18:02 CEST - Forced devcon instance restart
- ## T-024 - 2026-04-29 18:04 CEST - No-reboot disable/enable after bind
- ## T-025 - 2026-04-29 18:05 CEST - Explicit service image-load diagnostic
- ## T-025 log follow-up - 2026-04-29 18:06 CEST
- ## T-026 - 2026-04-29 18:07 CEST - Restart after explicit service load
- ## T-027 - 2026-04-29 18:16 CEST - Build-only cleanup after skill/tool review
- ## T-028 - 2026-04-30 00:56 CEST - Prefer WDDM2.0 registration
- ## T-029 - 2026-04-30 00:59 CEST - Add QUERYSEGMENT2/QUERYSEGMENT3 responses
- ## T-030 - 2026-04-30 01:12 CEST - Fast cycle recovered, runtime still Code 43
- ## T-031 - 2026-04-30 08:18 CEST - KMD instrumentation patch build gate
- ## T-032 - 2026-04-30 08:20 CEST - Instrumented KMD runtime test

### High-Level Combination Coverage (already tested)
- No-reboot guarded bind loops with automatic fallback to `display.inf`
- Custom BC250 KMD packaging with unique service/file names per iteration
- Explicit `sc start` diagnostic and post-service device restarts
- WDDM registration/version preference changes
- `QueryAdapterInfo` expansion (`QUERYSEGMENT2/3`, `WDDMDEVICECAPS`, `GPUPCAPS`, `DEVICE_TYPE_CAPS`, `QUERYSEGMENTCOUNT`)
- Build-pipeline stability fixes (MSVC PDB lock mitigation)
- Radeon `u0397406.inf` ID insertion attempts across multiple model decorations
- INF restaging/rebinding/reboot cycles with continued selection of `display.inf`
- Forced `devcon` install attempts with SetupAPI capture

### Last Confirmed Anti-Pattern (do not repeat unchanged)
- Re-running `pnputil /add-driver u0397406.inf /install` without changing signature trust/cat/package identity: repeatedly stages but does not become active bind.

## 14) Mandatory Signing Gate (Hard Rule)
- Every driver test package MUST be signed before install/bind attempts.
- No exceptions: unsigned or partially signed packages are invalid test data and must be rejected.
- Required pre-bind checks per iteration:
- Generate/refresh catalog after INF changes.
- Sign catalog and all changed binaries with the test cert.
- Verify signatures with signtool verify before install.
- Confirm cert trust chain on target (TrustedPublisher/Root as required by test policy).
- If signature verification fails, STOP iteration and mark as invalid (do not count as runtime driver result).
- Reason: unsigned paths distort rank/selection (Signer Score) and produce misleading outcomes.

## 15) New Critical Finding (T-033)
- A fully signed, freshly cloned Radeon package with BC-250 IDs can be made best-ranked for the PCI instance (ank 00CF0001, Authenticode signer score) and selected by SetupAPI.
- Despite selection, runtime still fails with:
- PCI instance: CM_PROB_FAILED_POST_START
- Additional node: ROOT\\DISPLAY\\0000 with CM_PROB_FAILED_ADD
- Therefore, current blocker is not INF ranking alone; it is post-bind AMD display miniport/runtime initialization on BC-250.

## 16) Signed Map Sweep Result (T-034)
- Tested mappings: ti2mtag_Navi14, ti2mtag_Navi21, ti2mtag_Legacy.
- Outcome for all: CM_PROB_FAILED_POST_START on PCI adapter after AMD bind (oem9.inf, mduw23g).
- All runs recovered to safe baseline via rollback (display.inf, CM_PROB_NONE).
- Actionable conclusion: changing only INF model-to-section mapping among these candidates does not resolve BC-250 runtime start failure.

## 17) Signed Map Extension Result (T-035)
- Additional mappings tested: ti2mtag_Navi23, ti2mtag_Mendocino, ti2mtag_Navi31.
- All produced the same runtime result: CM_PROB_FAILED_POST_START on PCI adapter with mduw23g after AMD bind.
- Strong conclusion: changing AMD install section mapping alone is now exhaustively low-yield across multiple families.

## 18) Signed Map Continuation (T-036)
- Added mappings tested: ti2mtag_Navi24, ti2mtag_Phoenix.
- Both produce the same post-start failure (Code 43) and same service path (mduw23g) with successful rollback.

## 19) Signed Map Continuation (T-037)
- Newly tested mappings: ti2mtag_Navi32, ti2mtag_DragonRange, ti2mtag_Rembrandt.
- All runs: signed package selected, then CM_PROB_FAILED_POST_START on PCI device with service mduw23g; rollback to display.inf succeeded.
- Mapping-only strategy is now effectively exhausted across exposed major families in this INF.

## 20) Runtime Telemetry Result (T-038/T-039)
- Added 20-second post-bind telemetry capture with focused System log slice.
- Baseline signed Navi10: still Code 43 post-start.
- Service-perturbed signed Navi10 (Crash Defender + External Events forced demand): same Code 43.
- Inference: failure is not explained by AMD helper service startup policy; root cause remains in the display miniport/runtime initialization after bind.

## 21) Service-Policy Perturbation (T-040)
- Forced mduw23g to uto and running before signed Navi10 bind.
- Bind flow still reconfigured service policy and ended in CM_PROB_FAILED_POST_START (Code 43).
- This further reduces likelihood that simple service start policy is the root cause.

## 22) CM_PROB Recovery Playbook (T-041)
- Symptom: baseline occasionally drifts to display.inf + CM_PROB_FAILED_POST_START and blocks fast loops.
- Working no-reboot fix on BC-250:
- Remove ROOT\\DISPLAY\\0000 phantom device.
- Delete stale test packages (oem9, oem21) from DriverStore.
- pnputil /scan-devices, remove/re-enumerate PCI display instance, force display.inf rebind, restart device.
- Verified outcome: returns to CM_PROB_NONE baseline.

## 23) Interpretation of 0xC01E0438 for this workflow
-  xC01E0438 maps to STATUS_GRAPHICS_NOT_POST_DEVICE_DRIVER (Microsoft error reference).
- In practice here it appears when the display stack rejects the attempted active display miniport path and falls back/stops with Code 43.
- This supports current strategy: treat it as runtime-init/post-device-state failure, not an INF-signing/ranking issue.
