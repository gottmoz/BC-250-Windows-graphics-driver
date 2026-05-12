# PS5UPDATE.PUP extraction notes - 2026-04-29

Input: `C:\Users\jimmy\Downloads\PS5UPDATE.PUP`

## Result

The file is a valid PS5 outer `SLB2` update wrapper. The wrapper exposes one inner payload, `PS5UPDATE1.PUP`, but that payload appears encrypted or otherwise intentionally opaque.

## Extracted metadata

- Outer size: `1,246,464,000` bytes
- Outer magic: `SLB2`
- Outer SLB2 version: `3`
- Outer flags: `0x00010000`
- Outer entry count: `1`
- Outer MD5: `41733cde5847ee2a63a253df94188c88`
- Outer SHA256: `a69f5ddf3b0f963407f4d2a9abf0968061e9865571cd0c84631d262c7201f806`

## Entry table

| Index | Name | Offset | Size | End |
|---:|---|---:|---:|---:|
| 0 | `PS5UPDATE1.PUP` | `0x400` / `1024` | `1,246,462,813` | `1,246,463,837` |

## Inner payload

- Inner MD5: `5d67b4060deaa368d452caec3f796620`
- Inner SHA256: `a58b23459533f1d7161b92e83194c73388f518f47f60cc208e1395407e1cdcdd`
- Inner entropy: `7.999999871893169` bits/byte
- First bytes: `54 14 f5 ee 10 01 01 32 ...`

The entropy is effectively maximum for byte data. The targeted hits for `AMD`, `gfx`, `GFX`, `PFP`, `MEC`, `SMU`, `DCN`, etc. are not reliable because their surrounding bytes look random and are consistent with coincidental matches inside encrypted data.

## Driver relevance

This file does not currently expose usable AMD GPU firmware blobs, PM4 tables, register init tables, or shader compiler data. Public PS5 PUP references mention filenames such as `oberon_sec_ldr_c0.bin`, `kernel.bin`, `ssd0.system_b`, and `ssd0.system_ex_b`, but those are inside the encrypted/decrypted-stage payload, not visible in this local file as-is.

For BC-250 work, this means the PUP is not immediately useful unless we obtain a legally decrypted PS5 update payload or a mounted/decrypted PS5 filesystem image. If that exists, the useful next searches are: `amdgpu`, `gfx10`, `gfx1013`, `navi`, `oberon`, `PFP`, `ME`, `MEC`, `SMU`, `DCN`, `GC_`, firmware blobs, and register-init tables.

## Artifacts

- Parser: `tools\parse_ps5_pup.py`
- JSON report: `ps5_pup_analysis\ps5_pup_report.json`
- Printable strings sample: `ps5_pup_analysis\ps5_pup_strings_sample.txt`
