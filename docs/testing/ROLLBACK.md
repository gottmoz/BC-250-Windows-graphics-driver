# Recovery and Rollback Guide

Experimental graphics driver testing can leave the system with Code 43, black screen, boot loops, or broken display output. Prepare rollback before testing.

## Before installing a test driver

1. Confirm you can reach Safe Mode.
2. Confirm you have admin access.
3. Keep a second display path if possible.
4. Create a restore point or full backup.
5. Save the previous known-good driver package.

## Basic rollback

Open PowerShell as Administrator.

List display devices:

```powershell
pnputil /enum-devices /class Display
```

List installed driver packages:

```powershell
pnputil /enum-drivers
```

Find the relevant `oemXX.inf`, then remove:

```powershell
pnputil /delete-driver oemXX.inf /uninstall /force
```

Reboot.

## Safe Mode rollback

If normal boot is broken:

1. Boot into Windows Recovery Environment.
2. Select Safe Mode.
3. Open PowerShell or Command Prompt as Administrator.
4. Run the `pnputil` commands above.
5. Reboot normally.

## Useful boot options

These may be useful during kernel/driver bring-up, depending on your test environment:

```powershell
bcdedit /enum
```

Do not change boot options unless you know why you need them. Always record any boot option changes in your test report.

## Report recovery outcome

Every failed test should include:

```text
Failure mode:
Could enter Safe Mode:
Rollback method:
Rollback successful:
Data/logs recovered:
Reinstall required:
```
