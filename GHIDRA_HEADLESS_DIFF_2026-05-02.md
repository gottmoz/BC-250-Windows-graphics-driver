# Ghidra Headless Diff (2026-05-02)

## Scope
- Custom driver: `C:\BC250_Driver\amdbc250kmd.sys`
- Reference driver: `C:\Windows\System32\DriverStore\FileRepository\u0397406.inf_amd64_52036240504cdbc8\B397164\amdkmdag.sys`
- Tool: Ghidra 12.0.4 headless on BC-250

## Environment fixes required
1. Install Java 21 JDK (Java 17 JRE was insufficient for Ghidra 12).
2. Set `JAVA_HOME` + prepend `PATH` in headless shell.
3. Python post-scripts failed (`PyGhidra not available in this launch mode`), switched to Java post-script.

## Key outputs
### Custom `amdbc250kmd.sys`
- Entry point: `0x140001A70`
- Function count: `37`
- External libraries resolved during load:
  - `NTOSKRNL.EXE`
  - `HAL.DLL`
- Analysis status: succeeded.

### AMD `amdkmdag.sys`
- Entry point: `0x1400F33D0`
- Function count (discovered before timeout): `57395`
- External libraries resolved/requested during load:
  - `NTOSKRNL.EXE`
  - `HAL.DLL`
  - `NETIO.SYS` (not found in project library linkage phase)
- Analysis status: timed out at 300s (expected for huge binary), but script still executed and returned metadata.

## Interpretation
- Our KMD is structurally minimal compared to AMD KMD (orders-of-magnitude smaller execution surface).
- Loader-side imports are not obviously broken (both NTOSKRNL/HAL are linked similarly), so CM_PROB/STATUS likely sits in init/DDI contract/state setup rather than missing base kernel imports.
- AMD driver has additional subsystem dependencies and much deeper init graph (`NETIO.SYS` reference and huge function space), reinforcing that our next gains should come from tighter init-gating and capability negotiation rather than broad section edits.

## Artifacts on BC-250
- `C:\BC250_Driver\ghidra\DumpDriverInfo.java`
- `C:\BC250_Driver\ghidra\out\custom_run2.log`
- `C:\BC250_Driver\ghidra\out\amd_run2.log`
