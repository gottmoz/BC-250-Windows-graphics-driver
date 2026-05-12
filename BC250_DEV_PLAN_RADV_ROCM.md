# BC-250 Driver Development Plan (with RADV/ROCm track)

Date: 2026-05-05
Scope: no-reboot headless workflow for BC-250 Windows driver bring-up.

## Confirmed current state (new information)

1. Failure signature is stable across all latest batches:
   - `CM_PROB_FAILED_DRIVER_ENTRY`
   - SetupAPI problem status `0xC0000059`
   - Kernel-PnP Event 219 status `0xC0000365` (`STATUS_FAILED_DRIVER_ENTRY`)
2. Runtime `DriverInitData.Version` permutations did not change outcome.
3. Compile-time `DXGKDDI_INTERFACE_VERSION` permutations did not change outcome.
4. DOD / callback-pruning variants did not change outcome.
5. Filter-driver conflict is unlikely (no UpperFilters/LowerFilters conflict found).
6. Safe fallback loop is working (`display.inf` / `BasicDisplay`, ProblemCode 0).

## RADV / ROCm artifact analysis summary

### What exists now

- AMDVLK (Vulkan UMD) artifacts:
  - `E:\world view\refs\R.ID\extract-B413136\Packages\Drivers\Display\WT6A_INF\B413136\amdvlk64.dll`
  - `E:\world view\refs\R.ID\extract-B413136\Packages\Drivers\Display\WT6A_INF\B413136\amdvlk32.dll`
- ROCm-adjacent runtime artifacts:
  - `amdhip64.dll`, `amdhip64_6.dll`, `amd_comgr.dll`, `amdocl64.dll`, `amdhsail64.dll`, `hiprt0200064.dll`

### What is missing

- True RADV runtime artifacts not present:
  - `radv*.dll`, `radv_icd*.json`, Mesa RADV Windows runtime artifacts.
- Complete ROCm stack components not present:
  - `hsa-runtime64.dll`, `rocminfo.exe`, `hipcc.exe`, `rocblas.dll`, `hiprtc.dll`, etc.

## Development plan

## Phase 1: Signature-lock diagnostics (short loops)

Goal: Keep reproducing the exact triad while collecting tighter internal evidence.

Batch format (<=3 min each):
1. Build + sign + guarded bind.
2. Immediate capture:
   - SetupAPI excerpt (`0xC0000059`)
   - Kernel-PnP 219 XML (status value)
   - SCM service events for current `amdbc250kmdt*`
3. Verify safe baseline restore.

Exit criteria:
- 3 consecutive runs with identical triad + complete evidence bundle.

## Phase 2: Entry-path isolation (single-variable only)

Goal: Locate exact failing stage in/around DriverEntry and Dxgk registration.

Priority toggles:
1. Add explicit status breadcrumbs that persist outside KdPrint (registry/event breadcrumb write before each return in DriverEntry path).
2. Narrow import surface in KMD binary (single change per run).
3. Validate INF/service creation path is not introducing stale service collisions.

Stop criteria:
- If 4 consecutive single-variable iterations show zero signature movement, switch focus to RADV/ROCm informed hypotheses.

## Phase 3: RADV/ROCm reverse-engineering track (parallel)

Goal: Mine high-value behavior from AMDVLK/HIP/COMGR to inform UMD/KMD contract and init expectations.

Primary targets:
1. `amdvlk64.dll`
2. `amdhip64_6.dll`
3. `amd_comgr.dll`
4. `amdocl64.dll`
5. `amdhsail64.dll`

Expected outputs:
- API/import map per binary
- Init-order candidates
- Required dependency list
- Potential contract mismatch candidates applicable to BC-250 stack

## Multi-agent execution model

Agent A - Failure triad and evidence correlation
- Owns: log extraction scripts and status classification.

Agent B - KMD entry-path instrumentation
- Owns: DriverEntry breadcrumb patching and minimal import-surface iterations.

Agent C - RADV/ROCm artifact RE
- Owns: AMDVLK/HIP/COMGR static analysis outputs.

Agent D - Integration coordinator
- Owns: per-iteration decision tree, stop/continue gates, and final hypothesis ranking.

## Ghidra / Binwalk execution notes

Current environment observations:
- `binwalk` Python package from PyPI can be incomplete in this environment.
- Ghidra appears present on BC-250 (`C:\Tools\ghidra`) but remote session stability is intermittent.

When host is stable, run:

```powershell
# Example ghidra headless template (adjust actual ghidra support path)
# analyzeHeadless <projectDir> <projectName> -import <binary> -postScript <script>

# Binwalk fallback approach
# Use known-good binwalk build or containerized run to avoid broken pip package.
```

## Immediate next actions

1. Resume SSH stability checks and complete one instrumentation batch in Phase 2.
2. Extract import/export dependency maps for `amdvlk64.dll` + `amdhip64_6.dll` first.
3. Start hypothesis cards from RE outputs and run 1-card-per-iteration loops.

## Quick binary triage (2026-05-05)

Method: static ASCII token scan + Authenticode verification on AMDVLK/HIP/COMGR binaries in `refs\R.ID`.

Findings:
- All inspected binaries are AMD-signed and valid.
- `amdvlk64.dll` and `amdvlk32.dll` expose strong Vulkan/LLVM/amdgpu/gfx10 token density and include `gfx1013` mention.
- `amdhip64.dll`, `amdhip64_6.dll`, and `amd_comgr.dll` show HIP/HSA/COMGR/Code Object signals consistent with ROCm-adjacent compute stack components.
- True RADV runtime artifacts are still not present in workspace.

Reference artifact:
- Existing Ghidra run record: `E:\world view\BC250-windowsDriverTest\GHIDRA_HEADLESS_DIFF_2026-05-02.md`
