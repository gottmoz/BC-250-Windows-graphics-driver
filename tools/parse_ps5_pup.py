#!/usr/bin/env python3
"""Parse the outer PS5 SLB2 PUP wrapper and report extractable metadata.

This does not decrypt PS5 inner update payloads. It is intended for quick
container-level inventory, hashes, entropy, and targeted string checks.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import re
import struct
from pathlib import Path

PATTERNS = [
    b"SLB2", b"ELF", b"SCE", b"AMD", b"Radeon", b"gfx", b"GFX",
    b"gfx10", b"gfx101", b"Navi", b"navi", b"Oberon", b"oberon",
    b"BC-250", b"Cyan", b"Skillfish", b"salina", b"titania", b"kernel",
    b"amdgpu", b"GC_", b"DCN", b"SMU", b"CP_", b"PFP", b"MEC",
]


def stream_hash(path: Path, offset: int = 0, size: int | None = None) -> tuple[str, str, float | None]:
    md5 = hashlib.md5()
    sha256 = hashlib.sha256()
    counts: collections.Counter[int] = collections.Counter()
    total = 0
    with path.open("rb") as f:
        f.seek(offset)
        left = size
        while left is None or left > 0:
            chunk_size = 1024 * 1024 if left is None else min(1024 * 1024, left)
            data = f.read(chunk_size)
            if not data:
                break
            if left is not None:
                left -= len(data)
            total += len(data)
            md5.update(data)
            sha256.update(data)
            counts.update(data)
    entropy = None
    if total:
        entropy = -sum((c / total) * math.log2(c / total) for c in counts.values())
    return md5.hexdigest(), sha256.hexdigest(), entropy


def parse_slb2(path: Path) -> dict:
    with path.open("rb") as f:
        header = f.read(0x20)
        if len(header) != 0x20:
            raise ValueError("file too small for SLB2 header")
        magic, version, flags, entry_count, size_sectors, r0, r1, r2 = struct.unpack("<8I", header)
        if magic.to_bytes(4, "little") != b"SLB2":
            raise ValueError(f"not an SLB2 wrapper: magic={magic:#x}")
        entries = []
        for index in range(entry_count):
            entry = f.read(48)
            start_sector, file_size, er0, er1 = struct.unpack("<4I", entry[:16])
            name = entry[16:48].split(b"\0", 1)[0].decode("ascii", "replace")
            entries.append({
                "index": index,
                "name": name,
                "start_sector": start_sector,
                "offset": start_sector * 512,
                "size": file_size,
                "end": start_sector * 512 + file_size,
            })
    return {
        "magic": "SLB2",
        "version": version,
        "flags": flags,
        "entry_count": entry_count,
        "size_in_sectors": size_sectors,
        "entries": entries,
    }


def targeted_findings(path: Path) -> list[dict]:
    results = []
    tail = b""
    offset = 0
    with path.open("rb") as f:
        while True:
            chunk = f.read(8 * 1024 * 1024)
            if not chunk:
                break
            data = tail + chunk
            base = offset - len(tail)
            for pattern in PATTERNS:
                start = 0
                count_for_pattern = sum(1 for r in results if r["pattern"] == pattern.decode("ascii", "replace"))
                while count_for_pattern < 50:
                    pos = data.find(pattern, start)
                    if pos < 0:
                        break
                    results.append({"pattern": pattern.decode("ascii", "replace"), "offset": base + pos})
                    count_for_pattern += 1
                    start = pos + 1
            tail = data[-128:]
            offset += len(chunk)
    return results


def strings_sample(path: Path, regions: list[tuple[str, int, int]]) -> list[dict]:
    out = []
    for name, offset, size in regions:
        with path.open("rb") as f:
            f.seek(offset)
            data = f.read(size)
        for match in re.finditer(rb"[ -~]{5,}", data):
            out.append({
                "region": name,
                "offset": offset + match.start(),
                "string": match.group(0).decode("ascii", "replace")[:200],
            })
            if len(out) >= 500:
                return out
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pup", type=Path)
    parser.add_argument("--out", type=Path, default=Path("ps5_pup_analysis"))
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    slb2 = parse_slb2(args.pup)
    outer_md5, outer_sha256, _ = stream_hash(args.pup)
    report = {
        "path": str(args.pup),
        "size": args.pup.stat().st_size,
        "outer": slb2,
        "outer_md5": outer_md5,
        "outer_sha256": outer_sha256,
    }
    if slb2["entries"]:
        first = slb2["entries"][0]
        inner_md5, inner_sha256, entropy = stream_hash(args.pup, first["offset"], first["size"])
        with args.pup.open("rb") as f:
            f.seek(first["offset"])
            head = f.read(256)
        report["first_entry"] = {
            **first,
            "md5": inner_md5,
            "sha256": inner_sha256,
            "entropy_bits_per_byte": entropy,
            "head_hex": head.hex(" "),
        }
        regions = [("outer_head", 0, 4096), ("first_entry_head", first["offset"], 2 * 1024 * 1024)]
    else:
        regions = [("outer_head", 0, 4096)]
    report["targeted_findings"] = targeted_findings(args.pup)
    report["strings_sample"] = strings_sample(args.pup, regions)

    (args.out / "ps5_pup_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (args.out / "ps5_pup_strings_sample.txt").write_text(
        "\n".join(f"{x['region']} 0x{x['offset']:x}: {x['string']}" for x in report["strings_sample"]),
        encoding="utf-8",
    )
    print(json.dumps({
        "size": report["size"],
        "outer": report["outer"],
        "first_entry": report.get("first_entry"),
        "report": str(args.out / "ps5_pup_report.json"),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
