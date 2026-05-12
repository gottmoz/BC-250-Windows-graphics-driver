# BC-250 Windows Driver - Execution Strategy for Secondary Agent

## MISSION
Install AMD graphics driver on BC-250 (Cyan Skillfish/GFX1013) at 192.168.50.200

## CRITICAL FINDING
Test Mode alone is insufficient. Windows driver ranking gives unsigned drivers Signer Score 0xFF (worst), causing not digitally signed failures. Must create and sign catalog.

## EXECUTION PLAN: AMD Radeon INF Modification

### PHASE 1: Prepare Environment
1) Enable Test Mode
```cmd
bcdedit /set testsigning on
bcdedit /set nointegritychecks on
shutdown /r /t 0
```

2) Install WDK + SDK
https://learn.microsoft.com/windows-hardware/drivers/download-the-wdk

### PHASE 2: Create Test Certificate (PowerShell Admin)
```powershell
$cert = New-SelfSignedCertificate `
    -Subject "CN=BC250 Test Certificate" `
    -Type CodeSigningCert `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(5)

New-Item -ItemType Directory -Force -Path C:\BC250_Certs | Out-Null
Export-Certificate -Cert "Cert:\LocalMachine\My\$($cert.Thumbprint)" -FilePath "C:\BC250_Certs\BC250_TestCert.cer" | Out-Null
Import-Certificate -FilePath "C:\BC250_Certs\BC250_TestCert.cer" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Import-Certificate -FilePath "C:\BC250_Certs\BC250_TestCert.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null
```

### PHASE 3: Modify AMD Driver
INF path:
`C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF\u0397406.inf`

Add BC-250 IDs in active model sections:
- `[ATI.Mfg.NTamd64.10.0.1..16299]`
- `[ATI.Mfg.NTamd64.10.0.1]`

Use mapping lines:
```inf
%AMD13FE.1% = ati2mtag_Navi10, PCI\VEN_1002&DEV_13FE
%AMD13FE.2% = ati2mtag_Navi10, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022
```

In `[Strings]` add:
```inf
AMD13FE.1 = "AMD BC-250 Graphics Adapter"
AMD13FE.2 = "AMD BC-250 Graphics Adapter (SUBSYS 00001022)"
```

### PHASE 4: Create and Sign Catalog
```cmd
cd "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64"
inf2cat.exe /driver:"C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF" /os:10_GE_X64
signtool.exe sign /v /s My /n "BC250 Test Certificate" /fd sha256 /t http://timestamp.digicert.com "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF\u0397406.cat"
signtool.exe verify /pa /v "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF\u0397406.cat"
```

### PHASE 5: Install Driver
```cmd
pnputil /add-driver "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF\u0397406.inf" /install
shutdown /r /t 0
```

## VERIFICATION
- `bcdedit | findstr testsigning` => Yes
- `signtool verify /pa ...` => Success
- Device Manager shows AMD BC-250
- `Get-PnpDevice` status OK

## RECOVERY
```powershell
devcon disable "PCI\VEN_1002&DEV_13FE*"
shutdown /r /t 0
```

## ROOT CAUSE SUMMARY
- Problem: BC-250 not detected by stock AMD driver
- Cause: Missing Device IDs in INF
- Blocker: Catalog signing required for effective PnP binding and ranking
- Solution: Modify INF, generate and sign catalog, install

## IMPORTANT ADDENDUM FROM LIVE TESTS
- Do not use `devcon /install` for this path: it may create `ROOT\DISPLAY\0000` phantom node.
- Prefer `pnputil /add-driver ... /install` and targeted `devcon update` only.
- Signed and best-ranked package can still fail at runtime with Code 43 on BC-250 (`CM_PROB_FAILED_POST_START`).
- Every iteration must end with rollback to `display.inf` if PCI adapter is not `CM_PROB_NONE`.
