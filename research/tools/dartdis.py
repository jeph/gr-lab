"""Linear disassembler for a Dart AOT libapp.so with blutter object-pool annotations.

blutter only emits code for functions that keep Code objects; with
dwarf_stack_traces_mode most app functions are missing from its asm/ output.
This walks the whole isolate instructions section, resolves object-pool loads
(x27 = PP) against blutter's pp.txt, and labels call targets with addNames.py.

Usage: dartdis.py <libapp.so> <blutter_out> <out_dir>
Writes <out_dir>/dis.txt (annotated listing) and <out_dir>/xrefs.json
(pool offset -> referencing function starts).
"""

import bisect
import json
import re
import sys
from pathlib import Path

from capstone import CS_ARCH_ARM64, CS_MODE_ARM, Cs
from elftools.elf.elffile import ELFFile

PP = "x27"
POOL_LINE = re.compile(r"^\[pp\+0x([0-9a-f]+)\] (.*)$")
NAME_LINE = re.compile(r'set_name\((0x[0-9a-f]+), "([^"]+)"\)')
ADD_PP = re.compile(r"^(x\d+), x27, #(0x[0-9a-f]+|\d+), lsl #12$")
LDR_BASE = re.compile(r"^(x\d+|w\d+), \[(x\d+), #(0x[0-9a-f]+|\d+)\]$")
LDP_BASE = re.compile(r"^(x\d+), (x\d+), \[(x\d+), #(0x[0-9a-f]+|\d+)\]$")
BL = re.compile(r"^#(0x[0-9a-f]+)$")


def load_pool(path: Path) -> dict[int, str]:
    pool = {}
    for line in path.read_text(errors="replace").splitlines():
        m = POOL_LINE.match(line)
        if m:
            pool[int(m.group(1), 16)] = m.group(2)[:240]
    return pool


def load_names(path: Path) -> dict[int, str]:
    names = {}
    for m in NAME_LINE.finditer(path.read_text()):
        if not m.group(2).endswith("_check"):
            names.setdefault(int(m.group(1), 16), m.group(2))
    return names


def main() -> None:
    libapp, blutter_out, out_dir = (Path(a) for a in sys.argv[1:4])
    out_dir.mkdir(parents=True, exist_ok=True)
    pool = load_pool(blutter_out / "pp.txt")
    names = load_names(blutter_out / "ida_script" / "addNames.py")

    with libapp.open("rb") as fh:
        elf = ELFFile(fh)
        sym = next(
            s
            for s in elf.get_section_by_name(".dynsym").iter_symbols()
            if s.name == "_kDartIsolateSnapshotInstructions"
        )
        start, size = sym["st_value"], sym["st_size"]
        seg = next(
            s
            for s in elf.iter_segments()
            if s["p_type"] == "PT_LOAD"
            and s["p_vaddr"] <= start < s["p_vaddr"] + s["p_filesz"]
        )
        fh.seek(seg["p_offset"] + start - seg["p_vaddr"])
        code = fh.read(size)

    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.skipdata = True
    insns = [(a, mnem, ops) for a, _, mnem, ops in md.disasm_lite(code, start)]

    starts = set(names)
    for _, mnem, ops in insns:
        if mnem == "bl":
            m = BL.match(ops)
            if m:
                starts.add(int(m.group(1), 16))
    starts = sorted(a for a in starts if start <= a < start + size)

    def func_of(addr: int) -> int:
        idx = bisect.bisect_right(starts, addr) - 1
        return starts[idx] if idx >= 0 else start

    xrefs: dict[int, set[int]] = {}
    pending: dict[str, int] = {}
    with (out_dir / "dis.txt").open("w") as out:
        next_start = 0
        for addr, mnem, ops in insns:
            if next_start < len(starts) and addr >= starts[next_start]:
                while next_start < len(starts) and starts[next_start] <= addr:
                    next_start += 1
                pending.clear()
                out.write(f"\n== func {addr:#x} {names.get(addr, '')}\n")
            note = ""
            offs: list[int] = []
            m = ADD_PP.match(ops) if mnem == "add" else None
            if m:
                pending[m.group(1)] = int(m.group(2), 0) << 12
            elif mnem.startswith("ldr"):
                m = LDR_BASE.match(ops)
                if m:
                    base, imm = m.group(2), int(m.group(3), 0)
                    if base == PP:
                        offs = [imm]
                    elif base in pending:
                        offs = [pending[base] + imm]
                dst = ops.split(",", 1)[0]
                pending.pop(dst.replace("w", "x", 1), None)
            elif mnem == "ldp":
                m = LDP_BASE.match(ops)
                if m:
                    base, imm = m.group(3), int(m.group(4), 0)
                    if base == PP:
                        offs = [imm, imm + 8]
                    elif base in pending:
                        offs = [pending[base] + imm, pending[base] + imm + 8]
            elif mnem == "bl":
                m = BL.match(ops)
                if m:
                    note = names.get(int(m.group(1), 16), "")
            if offs:
                note = " | ".join(f"[pp+{o:#x}] {pool.get(o, '?')}" for o in offs)
                fn = func_of(addr)
                for o in offs:
                    xrefs.setdefault(o, set()).add(fn)
            out.write(
                f"{addr:#x}: {mnem} {ops}" + (f"  ; {note}" if note else "") + "\n"
            )

    (out_dir / "xrefs.json").write_text(
        json.dumps(
            {
                f"{k:#x}": sorted(f"{v:#x}" for v in vs)
                for k, vs in sorted(xrefs.items())
            }
        )
    )
    print(
        f"{len(insns)} insns, {len(starts)} function starts, {len(xrefs)} pool offsets referenced"
    )


if __name__ == "__main__":
    main()
