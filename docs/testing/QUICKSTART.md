# Tester Quickstart

This is the short version for contributors who want to help without reading the full test plan first.

## 1. Prepare recovery

Do not continue unless you can recover the machine.

Minimum:

- Admin access
- Safe Mode access
- Physical access or reliable remote recovery
- A way to remove a broken driver

## 2. Collect baseline logs

Open PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tools\windows\collect-bc250-logs.ps1 -TestStage T0 -Commit baseline -Result before-install
```

Attach the generated zip to a GitHub issue using the **Test result** template.

## 3. Install only one test build

Install the driver build you are testing.

Record:

```text
Build / commit:
VRAM setting:
CommitLimit:
UMA flags:
Child path behavior:
```

## 4. Reboot once

After reboot, collect logs again:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tools\windows\collect-bc250-logs.ps1 -TestStage T1 -Commit YOUR_COMMIT -Result YOUR_RESULT
```

Use result names like:

```text
loads
code43
black-screen
bsod
no-output
```

## 5. Report

Open a GitHub issue with:

- Test stage
- Build/commit
- Hardware variant
- Windows version
- Driver settings
- Result
- Log zip

## 6. Do not combine variables

Please do not change VRAM size, UMA flags, and child path in the same test. One build, one idea.
