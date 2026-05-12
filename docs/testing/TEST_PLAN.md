# BC-250 Windows Graphics Driver Test Plan

This document defines the shared test plan for collecting useful data from many BC-250 / PS5-derived APU users.

The goal is not just to find out whether a build "works". The goal is to collect comparable data across different hardware, Windows versions, driver settings, and boot/display conditions.

## Golden rule

Change **one variable at a time**.

A useful report looks like this:

```text
Build A:
- VRAM = 8192 MB
- CommitLimit unchanged
- Result: Code 43

Build B:
- Same as Build A, but CommitLimit = Size
- Result: driver loads, display detected, no output
```

A hard-to-use report looks like this:

```text
Changed VRAM, UMA flags, child status, install method, and Windows version.
It crashed.
```

## Test stages

Testing is split into stages so many users can contribute without mixing results.

| Stage | Purpose | Risk | Who should run it |
|---|---|---:|---|
| T0 | Inventory only, no driver changes | Low | Everyone |
| T1 | Install/build smoke test | Medium | Users with recovery access |
| T2 | `QuerySegment3` / memory contract tests | Medium | Driver testers |
| T3 | Display child path tests | Medium | Driver testers |
| T4 | VRAM size matrix | Medium/High | Driver testers |
| T5 | Long-run stability | High | Stable-ish systems only |
| T6 | Regression comparison | Medium | Repeat testers |

## Required recovery setup

Before testing experimental graphics drivers:

- Have physical access or remote recovery access.
- Know how to boot Safe Mode.
- Know how to remove/roll back the driver.
- Keep another display path if possible.
- Keep notes per boot.
- Do not test on a machine you cannot afford to reinstall.

Recommended recovery commands to keep nearby:

```powershell
# List display devices
pnputil /enum-devices /class Display

# List installed driver packages
pnputil /enum-drivers

# Remove a driver package after identifying the oemXX.inf name
pnputil /delete-driver oemXX.inf /uninstall /force
```

## What every tester should collect

Every test result should include:

```text
Tester name / handle:
Date:
Build / commit:
Branch:
Driver package name:
Test stage:
Hardware variant:
BIOS / firmware notes:
Windows version:
Install method:
Display connection:
Monitor model:
Recovery method available:
```

Driver-specific settings:

```text
VRAM reported:
CommitLimit:
Segment Size:
Aperture / CPU-visible flags:
UMA flags:
GTT settings:
QueryChildRelations behavior:
QueryChildStatus behavior:
StatusConnection behavior:
```

Result:

```text
Driver loads:
Device Manager status:
Error code:
Display output:
Display detected:
Resolution available:
Black screen:
BSOD:
Reboot loop:
Can recover without reinstall:
```

Logs:

```text
Event Viewer export:
setupapi.dev.log:
DxDiag output:
pnputil output:
Driver debug log:
Screenshots/photos:
```

## File naming convention

Use consistent names when attaching logs.

```text
YYYY-MM-DD_commit_stage_result_filename.ext
```

Examples:

```text
2026-05-12_abcdef1_T2_code43_setupapi.dev.log
2026-05-12_abcdef1_T2_code43_dxdiag.txt
2026-05-12_abcdef1_T2_black-screen_eventviewer.evtx
```

## Stage T0: Inventory baseline

Purpose: collect system data before any risky driver changes.

Run:

```powershell
mkdir C:\BC250Logs

systeminfo > C:\BC250Logs\systeminfo.txt
dxdiag /t C:\BC250Logs\dxdiag.txt
pnputil /enum-devices /class Display > C:\BC250Logs\display-devices-before.txt
pnputil /enum-drivers > C:\BC250Logs\drivers-before.txt
Get-ComputerInfo > C:\BC250Logs\computerinfo.txt
Get-PnpDevice -Class Display | Format-List * > C:\BC250Logs\pnp-display-before.txt
```

Optional:

```powershell
Get-CimInstance Win32_VideoController | Format-List * > C:\BC250Logs\video-controller-before.txt
```

Report this as a T0 issue.

## Stage T1: Install/build smoke test

Purpose: confirm whether the driver package installs and how Windows reports the device.

Procedure:

1. Start from T0 baseline.
2. Install the test driver.
3. Reboot once.
4. Collect logs.
5. Record Device Manager status.
6. Roll back if needed.

Collect:

```powershell
mkdir C:\BC250Logs

pnputil /enum-devices /class Display > C:\BC250Logs\display-devices-after.txt
pnputil /enum-drivers > C:\BC250Logs\drivers-after.txt
Get-PnpDevice -Class Display | Format-List * > C:\BC250Logs\pnp-display-after.txt
Get-CimInstance Win32_VideoController | Format-List * > C:\BC250Logs\video-controller-after.txt
dxdiag /t C:\BC250Logs\dxdiag-after.txt

Copy-Item C:\Windows\INF\setupapi.dev.log C:\BC250Logs\setupapi.dev.log -Force
```

Export Event Viewer logs:

```powershell
wevtutil epl System C:\BC250Logs\System.evtx
wevtutil epl Application C:\BC250Logs\Application.evtx
wevtutil epl Microsoft-Windows-Kernel-PnP/Configuration C:\BC250Logs\Kernel-PnP-Configuration.evtx
```

## Stage T2: Segment consistency test

Purpose: test whether `QuerySegment3` becomes more stable when `CommitLimit = Size`.

Only change:

```text
QuerySegment3:
  CommitLimit = Size
```

Do not change:

- VRAM size
- UMA flags
- child path
- install method
- Windows version

Expected useful outcomes:

| Outcome | Meaning |
|---|---|
| Code 43 becomes driver load | Strong positive signal |
| Code 43 changes error details | Useful partial signal |
| No change | Still useful |
| Worse behavior | Roll back, log exact failure |

Required report fields:

```text
Segment Size:
CommitLimit:
DedicatedVideoMemory reported:
SharedSystemMemory reported:
Device Manager status:
DxDiag result:
```

## Stage T3: Strict display child path

Purpose: test deterministic child reporting.

Apply after T2 only.

Expected behavior:

```text
QueryChildRelations:
  expose exactly one valid child

QueryChildStatus:
  accept only ChildUid == 0

StatusConnection:
  report connected for ChildUid == 0
```

Do not change VRAM/UMA in the same build.

Test cases:

| Case | Procedure | Expected data |
|---|---|---|
| T3-A | Boot with monitor connected | Device/display detection |
| T3-B | Boot without monitor, connect after login | Hotplug-ish behavior |
| T3-C | Reboot 3 times with same cable/monitor | Determinism |
| T3-D | Try another monitor/cable if available | Display-path sensitivity |

Record:

```text
Child count:
ChildUid accepted:
StatusConnection:
Monitor detected:
Output visible:
Resolution list:
Black screen:
```

## Stage T4: VRAM size matrix

Purpose: test PS5-aligned conservative VRAM reports.

Prerequisite:

- T2 is applied.
- T3 is applied if stable.
- No UMA flag changes.

Test one size per build:

| Test | VRAM report |
|---|---:|
| T4-A | 512 MB |
| T4-B | 1024 MB |
| T4-C | 2048 MB, optional |
| T4-D | 8192 MB baseline comparison |

For each test:

1. Build with one VRAM value.
2. Install.
3. Reboot.
4. Collect logs.
5. Roll back or reset before the next value.
6. Report as separate issue or separate clearly marked comment.

Record:

```text
VRAM configured:
VRAM reported by Windows:
CommitLimit:
Segment Size:
Device Manager status:
DxDiag result:
Crash/Code 43/black screen:
```

## Stage T5: Long-run stability

Only run if the driver loads consistently enough to recover.

### T5-A: Boot loop stability

Procedure:

1. Cold boot.
2. Wait until Windows is fully loaded.
3. Record status.
4. Shut down fully.
5. Repeat 10 times.

Report:

```text
Successful boots:
Failed boots:
Failure number:
Failure mode:
Can recover:
```

### T5-B: Idle stability

Procedure:

1. Boot once.
2. Leave idle for 1 hour.
3. Record status.
4. Leave idle for 4 hours.
5. Record status.
6. Optional: leave idle for 8 hours.

Record:

```text
Display sleep:
System sleep:
Wake behavior:
Driver reset:
Event Viewer warnings/errors:
```

### T5-C: Display behavior

Procedure:

1. Boot with monitor connected.
2. Change resolution if available.
3. Let display sleep.
4. Wake display.
5. Reboot with monitor disconnected.
6. Connect monitor after login.

Record:

```text
Monitor detection:
Available resolutions:
Output after wake:
Output after reconnect:
```

### T5-D: Memory pressure smoke test

Only if recoverable.

Suggested safe-ish checks:

```powershell
dxdiag /t C:\BC250Logs\dxdiag-memory-smoke.txt
Get-CimInstance Win32_VideoController | Format-List * > C:\BC250Logs\video-controller-memory-smoke.txt
```

Avoid heavy GPU workloads until basic stability is known.

## Stage T6: Regression comparison

Purpose: determine exactly when behavior changed.

Use two builds:

```text
Known previous build:
New build:
```

Run the same test on both builds, ideally on the same hardware and same Windows installation.

Report:

```text
Previous build result:
New build result:
Only changed variable:
Logs from both:
```

## Suggested GitHub labels

Create these labels:

```text
test-result
bug
crash
code-43
black-screen
bsod
display-child
memory-segment
vram-512
vram-1024
vram-8192
long-run
needs-logs
good-signal
regression
```

## Maintainer triage checklist

For each incoming test result:

```text
[ ] Build/commit included
[ ] Hardware included
[ ] Windows version included
[ ] Exact test stage included
[ ] One variable changed
[ ] Logs attached
[ ] Result is reproducible
[ ] Follow-up needed
```

Mark reports that changed too many variables as `needs-logs` or ask the tester to rerun a smaller test.
