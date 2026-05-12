# Test Matrix

This matrix helps contributors run comparable tests.

## Core bring-up matrix

| ID | Base | Change | VRAM | UMA | Child path | Goal |
|---|---|---|---:|---|---|---|
| T1-A | baseline | install only | existing | unchanged | unchanged | install/load smoke |
| T2-A | T1-A | `CommitLimit = Size` | existing | unchanged | unchanged | segment consistency |
| T3-A | T2-A | strict child path | existing | unchanged | strict | display-child determinism |
| T4-A | T3-A | VRAM report | 512 MB | unchanged | strict | conservative VRAM |
| T4-B | T3-A | VRAM report | 1024 MB | unchanged | strict | conservative VRAM |
| T4-C | T3-A | VRAM report | 8192 MB | unchanged | strict | large baseline comparison |

## UMA matrix, later only

Run this only after T2/T3/T4 have produced a stable-ish baseline.

| ID | Base | UMA variable | Expected data |
|---|---|---|---|
| U1 | best T4 build | UMA flag A only | load/display/memory report |
| U2 | best T4 build | UMA flag B only | load/display/memory report |
| U3 | best T4 build | UMA flag C only | load/display/memory report |

Do not combine UMA variables until individual results are known.

## Long-run matrix

| ID | Duration | Procedure | Pass signal |
|---|---:|---|---|
| L1 | 10 boots | cold boot loop | same result each boot |
| L2 | 1 hour | idle desktop | no reset/crash |
| L3 | 4 hours | idle desktop | no reset/crash |
| L4 | 8 hours | idle desktop | no reset/crash |
| L5 | display sleep/wake | let display sleep, wake | output returns |
| L6 | monitor reconnect | disconnect/reconnect | detection stable |
