# BC-250 Driver Stats (2026-05-14)

Generated: 2026-05-14 09:42:58 +02:00

## Totals
- Test entries (T-###): 20
- Result lines: 35
- PASS: 1
- FAIL: 25
- BUILD FAIL: 3

## Key Signals
- status_0xC0000059: TEST_MATRIX=102, PROGRESS=22
- status_0xC00000E5: TEST_MATRIX=21, PROGRESS=14
- problem_0x15_status_0x0: TEST_MATRIX=19, PROGRESS=8
- code_43: TEST_MATRIX=45, PROGRESS=5
- cm_prob_failed_driver_entry: TEST_MATRIX=71, PROGRESS=9
- cm_prob_failed_add: TEST_MATRIX=6, PROGRESS=5

## Recent Progress Markers
- ### 2026-05-07 22:30 CEST
- ### 2026-05-07 22:39 CEST
- ### 2026-05-07 22:59 CEST
- ### 2026-05-07 23:12 CEST
- ### 2026-05-07 23:34 CEST
- ### 2026-05-07 23:41 CEST
- ### 2026-05-07 23:45 CEST
- ### 2026-05-08 08:51 CEST
- ### 2026-05-08 16:45 CEST
- ### 2026-05-08 17:11 CEST
- ### 2026-05-08 19:53 CEST
- ### 2026-05-08 20:01 CEST

## Collaboration Next Steps
- Reproducera senaste stabila bas med hash-gate (B_EQ_C) innan varje test
- Halla DOD callback-shape som passerar init (inkl. ResetDevice) som fast baseline
- Logga AddDevice/StartDevice breadcrumbs till registry for varje iteration
- Publicera nya runs i TEST_MATRIX.md och PROGRESS.md med en-andring-per-test
