# BC-250 Volume LTSC Repair Runbook

## Why
Current host (`Windows 10 Enterprise LTSC 2021`, `EditionID=EnterpriseS`, `VOLUME_KMSCLIENT`) fails CU install with `0x800F081F` and RDP listener does not bind.

## Confirmed blockers
- `KB5082200` install repeatedly fails: `CBS_E_SOURCE_MISSING (0x800F081F)`
- In-place repair with LTSC **evaluation** media fails: `0xC1900215` (channel mismatch)

## Required media
- Non-evaluation **Windows 10 Enterprise LTSC 2021 Volume** ISO (x64, matching host language)

## Execution (on BC-250)
1. Mount ISO.
2. Run:
```cmd
D:\setup.exe /auto upgrade /dynamicupdate disable /showoobe none
```
3. Let repair complete and reboot.
4. Validate:
```powershell
Get-Service TermService,SessionEnv,UmRdpService
qwinsta
netstat -ano -p tcp | findstr :3389
```
5. Retry cumulative update after repair.

## Expected outcome
- RDP listener (`rdp-tcp`) restored
- `3389` listening
- `KB5082200` installs successfully
