# BC-250 Windows Graphics Driver

Experimental Windows graphics driver work for the AMD BC-250 / PS5-derived APU platform.

> Status: early bring-up and reverse-engineering. Expect crashes, failed boots, Code 43, black screens, and broken display paths. Do not test on a system you cannot recover.

## Project goal

The goal of this project is to get a stable Windows graphics driver path working on BC-250-style hardware by documenting, testing, and iterating on the minimum required display and memory-management behavior.

The current focus is not performance tuning. The first target is basic driver load stability, correct adapter/segment reporting, and deterministic display-child behavior.

## Background

Linux support for PS5-derived hardware appears to establish the VRAM contract before the kernel and amdgpu driver see the device. The loader reserves VRAM via `vram.txt`, with a common default of `0x20000000` / 512 MB.

That suggests Windows driver experiments should avoid assuming a normal desktop dGPU-style 8 GB visible VRAM model during early bring-up.

Relevant upstream/adjacent areas we are using as guidance:

- PS5 Linux loader VRAM reservation model
- PS5 Linux patches for platform bring-up, probe, and display handling
- Upstream amdgpu behavior around CPU-visible VRAM and GTT fallback paths
- Windows display miniport contracts for segment reporting and child-device status

## Current working theory

The most promising low-risk path is to make the Windows driver report a conservative and internally consistent memory/display contract before experimenting with UMA flags or larger VRAM sizes.

Current priority order:

1. Make `QuerySegment3` internally consistent.
2. Make child-device reporting strict and deterministic.
3. Test smaller PS5-aligned VRAM reports such as 512 MB and 1024 MB.
4. Change UMA-related flags only one variable at a time after the above is stable.

## Current development state

Research completed so far:

- PS5 Linux sets VRAM before kernel/amdgpu through the loader and `vram.txt`.
- The loader reserves the selected VRAM range in the memory map.
- `ps5-linux-patches` appears focused mostly on platform bring-up, probe, and display plumbing rather than rewriting core VRAM/GTT algorithms.
- Upstream amdgpu visible-VRAM edge cases and GTT fallback behavior are important references for stability.

Driver-side findings to apply:

- In `QuerySegment3`, set `CommitLimit = Size` consistently.
- Keep the display child path strict:
  - `QueryChildRelations` should expose one valid child.
  - `QueryChildStatus` should only accept `ChildUid == 0`.
  - `StatusConnection` should report connected for that child.
- Test VRAM reporting as 512 MB and 1024 MB before returning to large values such as 8192 MB.
- UMA flags should be tested later, one at a time.

## Proposed test series

Each iteration should be built, installed, rebooted, tested, logged, then either kept or rolled back before the next change.

### Iteration 1: Segment consistency

Change only:

```text
QuerySegment3:
  CommitLimit = Size
```

Keep existing VRAM reporting unchanged.

Record:

- Does the driver load?
- Device Manager status
- Code 43 or other error code
- BSOD or black screen behavior
- Relevant kernel/debug logs
- Reported segment size and commit limit

### Iteration 2: Strict child path

Keep Iteration 1 and add:

```text
QueryChildRelations:
  expose exactly one valid child

QueryChildStatus:
  accept only ChildUid == 0

StatusConnection:
  report connected for ChildUid == 0
```

Record:

- Whether display detection changes
- Whether boot/display behavior becomes more deterministic
- Any new Device Manager or Event Viewer errors

### Iteration 3: Conservative VRAM reports

Keep Iteration 1 and 2, then test VRAM sizes one at a time:

```text
512 MB
1024 MB
```

Recommended process:

1. Build with 512 MB.
2. Install, reboot, test, collect logs.
3. Roll back or reset to known-good state.
4. Build with 1024 MB.
5. Install, reboot, test, collect logs.
6. Compare against the previous 8192 MB behavior.

## Long-run testing plan

Once the driver reaches a state where it loads consistently, contributors can help by running longer repeatable tests.

### Long Run A: Boot stability

- Install the same build.
- Perform 10 cold boots.
- Record whether the device loads successfully each time.
- Record any Code 43, black screen, BSOD, or recovery behavior.

### Long Run B: Idle stability

- Boot into Windows.
- Leave the system idle for 1, 4, and 8 hours.
- Record display timeout, sleep, wake, and crash behavior.

### Long Run C: Display detection

- Boot with display connected.
- Boot with display disconnected, then connect after login.
- Change resolution if available.
- Test monitor sleep/wake.

### Long Run D: Memory pressure smoke test

Only run this if the system can be recovered easily.

- Open several GPU-aware applications.
- Trigger basic DirectX enumeration tools.
- Record whether memory reporting changes or driver reset occurs.

## How to report test results

Open a GitHub issue using the **Test result** template and include logs whenever possible.

Please attach logs instead of only summarizing them. Exact failure text matters.

Useful logs and files:

- Event Viewer export
- `C:\Windows\INF\setupapi.dev.log`
- Kernel/debug logs
- Photos/screenshots of Device Manager or BSOD
- Exact build/commit used

## Safety and recovery notes

This is experimental kernel/driver work. Before testing:

- Make sure you have remote access, safe mode access, or physical recovery access.
- Keep a known-good restore point or full disk backup.
- Test one variable at a time.
- Reboot after every driver change.
- Keep notes per boot.

## Development rules of thumb

- Prefer small, reversible commits.
- Do not mix VRAM-size changes with UMA-flag changes in the same test.
- Do not change display-child behavior and memory reporting in the same iteration unless the previous state is already documented.
- Any result is useful if it includes exact build, exact settings, and logs.

## References

- PS5 Linux loader: https://github.com/ps5-linux/ps5-linux-loader
- PS5 Linux image `vram.txt`: https://github.com/ps5-linux/ps5-linux-image/blob/main/boot/vram.txt
- PS5 Linux patches: https://github.com/ps5-linux/ps5-linux-patches
- amdgpu visible VRAM stable-fix discussion: https://lists.linaro.org/archives/list/linux-stable-mirror%40lists.linaro.org/message/U5AQUQCJPVE4OWZET7DSC6FZ3Q6KUM2R/
- amdgpu GTT fallback discussion: https://lists.freedesktop.org/archives/amd-gfx/2023-November/101737.html

## License

This project is licensed under the Apache License 2.0. See [`LICENSE`](LICENSE).

Do not copy code from other projects unless the license is compatible and the origin is documented.
