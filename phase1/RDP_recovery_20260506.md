# BC-250 RDP Recovery Run (2026-05-06)

## Target
- Host: `192.168.50.189`
- Access: SSH OK, RDP not listening

## What was tested
1. Verified baseline:
- `TermService` running
- `RDP-Tcp` registry enabled
- `fDenyTSConnections=0`
- `qwinsta` missing `rdp-tcp` listener
- `netstat` no TCP 3389 listener

2. Registry and service reset:
- Forced `PortNumber=3389`
- Enabled firewall group `Remote Desktop`
- Restarted `TermService`, `SessionEnv`, `UmRdpService`
- Result: no listener

3. Certificate path:
- Removed stale `SSLCertificateSHA1Hash`
- Generated new self-signed cert in `LocalMachine\My`
- Bound thumbprint to `RDP-Tcp` cert hash
- Result: no listener

4. Policy path:
- Set `fEnableWddmDriver=0` (TS policy)
- Restarted services
- Result: no listener

5. OS health repair:
- `sfc /scannow` => no integrity violations
- `DISM /RestoreHealth` with Win10 consumer ISO => success
- `DISM /RestoreHealth` with LTSC eval ISO index 1 => success
- Rebooted once and re-tested
- Result: no listener

6. In-place repair upgrade attempts:
- Consumer ISO fails at product key/edition
- LTSC eval ISO downloaded (4,898,582,528 bytes)
- Setup scan from LTSC eval fails with `0xC1900215` at `CDlpActionProductKeyValidate::SelectImageIndex`
- SetupDiag: abrupt downlevel failure `0xC1900215-0x40005`

## Key conclusion
- RDP stack is still non-functional despite successful servicing repairs.
- In-place repair is blocked by channel mismatch (installed OS is Volume `EnterpriseS`, media is Evaluation channel).

## Required next step
- Use **non-evaluation Windows 10 Enterprise LTSC 2021 (Volume channel) ISO** matching host language/arch for repair upgrade.
- Eval media is not accepted for this host installation channel.

## Local controller status
- Accidental local `SetupHost`/MCT processes are no longer running.
