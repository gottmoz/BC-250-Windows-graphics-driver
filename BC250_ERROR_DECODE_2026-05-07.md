# BC-250 Error Decode and Fix Direction (2026-05-07)

## Scope

This note decodes the errors seen in the latest headless batches and maps each to concrete fix actions.

## 1) Build Error in `NT05_pb64k_w20_u0`

### Observed

- Iterations `R1..R15` for `NT05` failed with `ITER_FAIL ... build_kmd code=1`.
- Isolated compile probe produced:
  - `error C2065: 'DXGKDDI_WDDMv2_0': undeclared identifier`
  - file: `amdbc250_kmd.c`, line ~221.

### Meaning

This is a **compile-time header compatibility issue**, not a runtime driver-start issue.
The current KM include set (`10.0.19041.0`) does not expose `DXGKDDI_WDDMv2_0` in the way the forced path expects.

### Evidence

- Probe output captured during isolated build run (`HOST=DESKTOP-BAHCDQS`) shows the exact compiler error.
- Related source reference:
  - `C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared\ntstatus.h` is available, but build itself uses 19041 include path for KM.

### Fix

Guard forced WDDM 2.0 constant usage with `#if defined(...)` fallback:

- If `AMDBC250_FORCE_WDDM_CAPS_LEVEL == 20` but `DXGKDDI_WDDMv2_0` is not defined, fallback to `DXGKDDI_WDDMv1_3` and log explicit fallback.

---

## 2) Runtime Event: `Problem Status 0xC00000E5`

### Meaning

`0xC00000E5` is `STATUS_INTERNAL_ERROR`.
Message text in SDK header: **"An internal error occurred."**

### Evidence

- `C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared\ntstatus.h:4190`
  - `#define STATUS_INTERNAL_ERROR ((NTSTATUS)0xC00000E5L)`
- Nearby message comment:
  - line 4188: `An internal error occurred.`

### Interpretation for BC-250

In Kernel-PnP Event 411, this status indicates a generic internal failure during driver/device start path.
It is broad; by itself it does not identify which DDI path failed.

---

## 3) Runtime Event: `Problem 0x15` with `Problem Status 0x0`

### Meaning

`Problem 0x15` maps to `CM_PROB_WILL_BE_REMOVED`.
In `cfg.h` comment: **"devinst will remove"**.

### Evidence

- `C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared\cfg.h:88`
  - `#define CM_PROB_WILL_BE_REMOVED (0x00000015) // devinst will remove`

### Interpretation for BC-250

This is typically a **device-instance lifecycle/teardown state**, not a final healthy start.
It often appears when PnP has decided to drop or rework the current devnode during/start after binding attempts.

---

## 4) Related Historical Status (already seen earlier)

`0xC01E0438` = `STATUS_GRAPHICS_NOT_POST_DEVICE_DRIVER`.
Meaning: **"The driver trying to start is not the same as the driver for the POSTed display adapter."**

Evidence:
- `C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared\ntstatus.h:18513`

---

## 5) Practical Solve Plan

1. **Fix compile path first**
- Patch forced WDDM=20 path so `NT05` compiles on 19041 headers.
- Re-enable `NT05` in batch and collect comparable runtime events.

2. **Prioritize signatures by quality**
- Treat `0x15 / 0x0` as "transitional/teardown" signature.
- Treat `0x0 / 0xC00000E5` as "internal start failure" signature.
- Continue ranking variants by increased `0x15/0x0` share only if accompanied by fewer hard failures and stable baseline recovery.

3. **Add tighter failure pinpointing**
- Keep existing first-fail and QueryAdapterInfo trace fields.
- Add one extra trace around post-start path/DDI callbacks to identify last successful stage before Event 411.

4. **Run next batch**
- Same controlled matrix, one variable at a time, with signed package + reboot cycle + baseline verification.
