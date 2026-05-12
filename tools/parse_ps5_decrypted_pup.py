#!/usr/bin/env python3
"""Parse and selectively unpack decrypted PS5 PUP fragments.

The logic follows zecoxao/ps5-pup-unpacker: normal entries are copied or
zlib-inflated; blocked entries use a companion table entry whose ID equals the
blocked entry index.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import zlib
from dataclasses import dataclass, asdict
from pathlib import Path

FILE_NAMES = {
    1: "eula.xml", 2: "updatemode.elf", 3: "emc_salina_a0.bin", 4: "mbr.bin",
    5: "kernel.bin", 6: "unk_06.bin", 7: "unk_07.bin", 8: "unk_08.bin",
    9: "unk_09.bin", 10: "CP.bin", 11: "titania.bls", 12: "version_name.xml",
    13: "emc_salina_b0.bin", 14: "eap_kbl.bin", 15: "bd_firm_info.json",
    16: "emc_salina_c0.bls", 17: "floyd_salina_c0.bls", 18: "usb_pdc_salina_c0.bls",
    20: "emc_salina_d0.bls", 21: "eap_kbl_2.bin", 22: "font.zip",
    256: "ariel_a0.bin", 257: "oberon_sec_ldr_a0.bin", 258: "oberon_sec_ldr_b0.bin",
    259: "oberon_sec_ldr_c0.bin", 260: "oberon_sec_ldr_d0.bin", 261: "oberon_sec_ldr_f0.bin",
    262: "oberon_sec_ldr_e0.bin", 752: "qa_test_1.pkg", 753: "qa_test_2.pkg", 754: "qa_test_3.pkg",
}
DEVICE_NAMES = {
    512: "dev/unk_512.bin", 513: "dev/wlanbt.bin", 514: "dev/unk_514.bin",
    515: "dev/ssd0.system_b", 516: "dev/ssd0.system_ex_b", 517: "dev/unk_517.bin",
    518: "dev/unk_518.bin", 519: "dev/ssd0.preinst",
}

@dataclass
class Entry:
    index: int
    flags: int
    offset: int
    compressed_size: int
    uncompressed_size: int
    name: str = ""
    table_for_index: int = -2

    @property
    def id(self) -> int:
        return self.flags >> 20

    @property
    def compressed(self) -> bool:
        return (self.flags & 8) != 0

    @property
    def blocked(self) -> bool:
        return (self.flags & 0x800) != 0

    @property
    def info(self) -> bool:
        return (self.flags & 1) != 0

    @property
    def attrs_hex(self) -> str:
        return hex(self.flags & ((1 << 20) - 1))

    @property
    def flags_hex(self) -> str:
        return hex(self.flags)


def safe_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_./-]+", "_", name).strip("/")


def prepare_name(entry: Entry, entries: list[Entry]) -> str:
    if entry.table_for_index >= 0:
        return f"tables/{entry.id}_for_{entries[entry.table_for_index].id}.img"
    if entry.id in FILE_NAMES:
        return f"{entry.id}_{FILE_NAMES[entry.id]}"
    if entry.id in DEVICE_NAMES:
        dev = DEVICE_NAMES[entry.id]
        parent, _, base = dev.rpartition("/")
        return f"{parent}/{entry.id}_{base}" if parent else f"{entry.id}_{base}"
    return f"unknown/{entry.id}.img"


def parse(path: Path) -> tuple[dict, list[Entry]]:
    with path.open("rb") as f:
        hdr = f.read(0x20)
        magic, unknown04, unknown08, flags_byte, unknown0b, header_size, hash_size, file_size, entry_count, hash_count, unknown1c = struct.unpack("<IIHBBHHQHHI", hdr)
        if magic != 0xEEF51454:
            raise ValueError(f"unexpected magic {magic:#x}")
        entries = []
        for i in range(entry_count):
            flags = struct.unpack("<I", f.read(4))[0]
            f.seek(4, 1)
            off, csz, usz = struct.unpack("<QQQ", f.read(24))
            entries.append(Entry(i, flags, off, csz, usz))
    for e in entries:
        if e.blocked:
            table = next((x for x in entries if x.info and x.id == e.index), None)
            if table is None:
                raise ValueError(f"blocked entry {e.index} has no table")
            table.table_for_index = e.index
    for e in entries:
        e.name = prepare_name(e, entries)
    header = {
        "magic": hex(magic), "unknown04": hex(unknown04), "unknown08": hex(unknown08),
        "flags_byte": flags_byte, "unknown0b": unknown0b, "header_size": header_size,
        "hash_size": hash_size, "file_size": file_size, "entry_count": entry_count,
        "hash_count": hash_count, "unknown1c": hex(unknown1c),
    }
    return header, entries


def read_entry_data(path: Path, entry: Entry) -> bytes:
    with path.open("rb") as f:
        f.seek(entry.offset)
        data = f.read(entry.compressed_size)
    if entry.compressed:
        return zlib.decompress(data)
    return data


def extract_entry(path: Path, entries: list[Entry], entry: Entry, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not entry.blocked:
        data = read_entry_data(path, entry)
        dest.write_bytes(data[:entry.uncompressed_size])
        return

    if not entry.compressed:
        with path.open("rb") as src, dest.open("wb") as out:
            src.seek(entry.offset)
            remaining = entry.compressed_size
            while remaining:
                data = src.read(min(1024 * 1024, remaining))
                if not data:
                    break
                out.write(data)
                remaining -= len(data)
        return

    table = next((x for x in entries if x.info and x.id == entry.index), None)
    if table is None:
        raise ValueError(f"blocked entry {entry.index} has no table")
    table_data = read_entry_data(path, table)
    block_size = 1 << (((entry.flags & 0xF000) >> 12) + 12)
    block_count = (entry.uncompressed_size + block_size - 1) // block_size
    tail_size = entry.uncompressed_size % block_size or block_size
    pos = 32 * block_count
    block_infos = []
    for _ in range(block_count):
        block_infos.append(struct.unpack_from("<II", table_data, pos))
        pos += 8

    with path.open("rb") as src, dest.open("wb") as out:
        src.seek(entry.offset)
        compressed_remaining = entry.compressed_size
        uncompressed_remaining = entry.uncompressed_size
        last_index = block_count - 1
        for i, (block_off, block_size_field) in enumerate(block_infos):
            unpadded_size = (block_size_field & ~0xF) - (block_size_field & 0xF)
            compressed_read_size = block_size
            block_is_compressed = False
            if entry.compressed:
                if unpadded_size != block_size:
                    compressed_read_size = block_size_field
                    if i != last_index or tail_size != block_size_field:
                        compressed_read_size &= ~0xF
                        block_is_compressed = True
                if block_off != 0:
                    src.seek(entry.offset + block_off)
                    out.seek(i * block_size)
            else:
                compressed_read_size = min(block_size, compressed_remaining)
                src.seek(entry.offset + i * block_size)
            payload = src.read(compressed_read_size - (block_size_field & 0xF if block_is_compressed else 0))
            if block_is_compressed:
                write = zlib.decompress(payload)
                write = write[:min(block_size, uncompressed_remaining)]
            else:
                write = payload
            out.write(write)
            compressed_remaining -= compressed_read_size
            uncompressed_remaining -= len(write)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pup", type=Path)
    ap.add_argument("--out", type=Path, default=Path("ps5_pup_dec_analysis/unpacked"))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--extract-small", action="store_true", help="extract entries <=64 MiB uncompressed")
    ap.add_argument("--extract-ids", default="", help="comma-separated entry IDs to extract")
    ns = ap.parse_args()
    header, entries = parse(ns.pup)
    report = {"header": header, "entries": [{**asdict(e), "id": e.id, "blocked": e.blocked, "compressed": e.compressed, "info": e.info, "attrs_hex": e.attrs_hex, "flags_hex": e.flags_hex} for e in entries]}
    ns.out.mkdir(parents=True, exist_ok=True)
    (ns.out / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if ns.list:
        for e in entries:
            print(f"{e.index:02d} id={e.id:<5} name={e.name:<32} flags={e.flags_hex:<10} attrs={e.attrs_hex:<8} off=0x{e.offset:x} c={e.compressed_size} u={e.uncompressed_size} blocked={e.blocked} comp={e.compressed} info={e.info}")
    ids = {int(x, 0) for x in ns.extract_ids.split(",") if x.strip()}
    for e in entries:
        if (ns.extract_small and e.uncompressed_size <= 64 * 1024 * 1024) or e.id in ids:
            if (e.flags & 0xF0000000) in (0xE0000000, 0xF0000000):
                continue
            dst = ns.out / safe_name(e.name)
            print(f"extract {e.index:02d} id={e.id} -> {dst}")
            extract_entry(ns.pup, entries, e, dst)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
