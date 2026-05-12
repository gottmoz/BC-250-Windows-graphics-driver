# Decrypted PS5 PUP analysis

Input: `C:\Users\jimmy\Downloads\PS5UPDATE1.PUP.dec`

## Container result

The file is a decrypted PS5/PS4-style PUP fragment, not an `SLB2` outer wrapper. Header magic is `0xEEF51454`. It contains 26 segment entries.

A Python unpacker was added at `tools\parse_ps5_decrypted_pup.py`. It ports the relevant logic from `zecoxao/ps5-pup-unpacker`: normal copy, zlib inflate, and blocked segment extraction using companion block-table entries.

## Extracted segment highlights

| ID | Name | Size | Result |
|---:|---|---:|---|
| 1 | `eula.xml` | 1,557,889 | Plain XML, not driver-relevant |
| 2 | `updatemode.elf` | 11,619,748 | Still PUP/SELF-style opaque high-entropy data |
| 5 | `kernel.bin` | 21,750,272 | High entropy, no reliable AMD/GPU strings |
| 11 | `titania.bls` | 9,062,912 | Nested SLB2 with `C3000005`..`C300000C`, high entropy |
| 14 | `eap_kbl.bin` | 276,480 | Firmware blob, high entropy |
| 16 | `emc_salina_c0.bls` | 454,144 | Nested SLB2 with `C0000001`, high entropy |
| 17 | `floyd_salina_c0.bls` | 240,128 | Nested SLB2 with `C0040001/2`, high entropy |
| 18 | `usb_pdc_salina_c0.bls` | 46,080 | Nested SLB2, not GPU |
| 259 | `oberon_sec_ldr_c0.bin` | 401,008 | Oberon secure loader, high entropy/opaque |
| 260 | `oberon_sec_ldr_d0.bin` | 401,344 | Oberon secure loader, high entropy/opaque |
| 513 | `wlanbt.bin` | 791,040 | Nested SLB2, not GPU |
| 515 | `ssd0.system_b` | 231,931,904 | exFAT filesystem image |
| 516 | `ssd0.system_ex_b` | 997,392,384 | exFAT filesystem image |

## exFAT filesystem findings

The large system images are valid exFAT filesystems and were parsed directly.

Graphics-related paths found in `ssd0.system_b`:

- `/common/lib/libSceAgc.sprx`
- `/common/lib/libSceAgcDriver.sprx`
- `/common/lib/libSceAgcVsh.sprx`
- `/common/lib/libSceGnmDriver.sprx`
- `/common/lib/libSceGnmDriverCompat1.sprx`
- `/common/lib/libSceGnmDriverForNeoMode.sprx`
- `/common/lib/libSceVideoOut.sprx`
- `/common/lib/libSceVideoOutSecondary.sprx`
- `/priv/lib/libSceComposite.sprx`
- `/sys/AgcCompositor.elf`
- `/sys/gpudump.elf`

Graphics-related paths found in `ssd0.system_ex_b`:

- `/common_ex/lib/libSceGLSlimClientVSH.sprx`
- `/common_ex/lib/libSceGLSlimServerVSH.sprx`
- `/common_ex/lib/libSceGLSlimVSH.sprx`
- `/app/NPXS40140/cdc/lib/libgnmawt.prx`

These files were extracted to `ps5_pup_dec_analysis\extracted_graphics_files`.

## Driver relevance

The decrypted PUP is useful for mapping PS5 component names and filesystem layout, but it does not directly provide usable AMD CP/PFP/ME/MEC/SMU/DCN firmware or register tables. The graphics libraries and tools are still SELF/SPRX containers with `0xEEF51454` headers and high entropy, so their code remains encrypted/opaque without SELF decryption.

Actionable takeaway for BC-250 driver work:

- This PUP does not unblock the Windows KMD Code 43/PnP binding issue.
- It confirms PS5 graphics userland names: `Agc`, `Gnm`, `VideoOut`, `GLSlim`, `gpudump`.
- It confirms Oberon secure loader blobs exist in the PUP, but they are not directly usable as AMD command processor microcode.
- Continue using Linux `amdgpu` and public AMD firmware naming (`navi10_pfp.bin`, `navi10_me.bin`, `navi10_mec.bin`) for CP bring-up research.

## Artifacts

- Parser/unpacker: `tools\parse_ps5_decrypted_pup.py`
- Segment manifest: `ps5_pup_dec_analysis\unpacked\manifest.json`
- Small extracted segments: `ps5_pup_dec_analysis\unpacked`
- Large extracted images: `ps5_pup_dec_analysis\unpacked_large\dev\515_ssd0.system_b`, `ps5_pup_dec_analysis\unpacked_large\dev\516_ssd0.system_ex_b`
- exFAT file listing: `ps5_pup_dec_analysis\exfat_file_listing.json`
- Interesting paths: `ps5_pup_dec_analysis\exfat_interesting_paths.json`
- Extracted graphics files: `ps5_pup_dec_analysis\extracted_graphics_files`
- Graphics hit scan: `ps5_pup_dec_analysis\extracted_graphics_hits.txt`
