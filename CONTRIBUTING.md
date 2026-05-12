# Contributing

Thanks for helping with BC-250 Windows Graphics Driver testing and development.

## What is useful right now

The most useful contributions are:

- Reproducible test results
- Logs from failed and successful boots
- Small, reversible driver changes
- Documentation of hardware variants
- Clear comparisons between one build and the next

## Testing rules

Please test one variable at a time.

Good test report:

```text
Commit A: 8192 MB VRAM, CommitLimit unchanged -> Code 43
Commit B: same as A, but CommitLimit = Size -> driver loads, no output
```

Bad test report:

```text
Changed VRAM, UMA flags, child status, and install method -> it crashed
```

## Before submitting code

- Keep commits small.
- Explain what the change is trying to prove.
- Include rollback notes when possible.
- Do not paste code copied from another project unless the license is compatible and the source is documented.
- Prefer issue-driven changes: one hypothesis, one patch, one test result.

## License of contributions

Unless explicitly stated otherwise, contributions are submitted under the Apache License 2.0.
