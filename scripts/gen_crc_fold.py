#!/usr/bin/env python3
# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
"""Emit parallel reflected CRC folds used by the DLL.

The serial LFSR (poly, LSB-first) is the specification. This script expands it
into a flat XOR mask per output bit so synthesis sees a balanced tree, not a
bit-serial chain. Output is included from rivet_pkg.sv.
"""

from __future__ import annotations

import random
from pathlib import Path

POLY32 = 0xEDB88320
POLY16 = 0xD008
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "rtl" / "pcie_ctrl" / "rivet_crc_fold.svh"


def step_bit(crc: int, din: int, poly: int, width: int) -> int:
    fb = (crc ^ din) & 1
    crc >>= 1
    if fb:
        crc ^= poly
    return crc & ((1 << width) - 1)


def step_bytes(crc: int, data: list[int], poly: int, width: int) -> int:
    for byte in data:
        for bit in range(8):
            crc = step_bit(crc, (byte >> bit) & 1, poly, width)
    return crc


def crc32_zero_cols(nbytes: int) -> list[int]:
    return [step_bytes(1 << bit, [0] * nbytes, POLY32, 32) for bit in range(32)]


def crc32_data_cols(nbytes: int) -> list[int]:
    data = []
    for bit in range(nbytes * 8):
        raw = [0] * nbytes
        raw[bit // 8] = 1 << (bit % 8)
        data.append(step_bytes(0, raw, POLY32, 32))
    return data


def mask_from_cols(cols: list[int], out_bit: int) -> int:
    mask = 0
    for bit, col in enumerate(cols):
        if (col >> out_bit) & 1:
            mask |= 1 << bit
    return mask


def apply_cols(val: int, cols: list[int]) -> int:
    acc = 0
    for out in range(32):
        mask = mask_from_cols(cols, out)
        if bin(val & mask).count("1") & 1:
            acc |= 1 << out
    return acc


def crc32_zero_py(crc_in: int, nbytes: int) -> int:
    if nbytes == 0:
        return crc_in
    q = nbytes >> 3
    r = nbytes & 7
    c = crc_in if q == 0 else apply_cols(crc_in, crc32_zero_cols(q * 8))
    return c if r == 0 else apply_cols(c, crc32_zero_cols(r))


def crc32_data32_py(data_bytes: list[int], nbytes: int) -> int:
    if nbytes == 0:
        return 0
    q = nbytes >> 3
    r = nbytes & 7
    words = [0, 0, 0, 0]
    for i, b in enumerate(data_bytes[:32]):
        words[i // 8] |= b << (8 * (i % 8))
    d8_cols = crc32_data_cols(8)
    d = [apply_cols(w, d8_cols) for w in words]
    if q == 0:
        df = 0
    elif q == 1:
        df = d[0]
    elif q == 2:
        df = apply_cols(d[0], crc32_zero_cols(8)) ^ d[1]
    elif q == 3:
        df = apply_cols(d[0], crc32_zero_cols(16)) ^ apply_cols(d[1], crc32_zero_cols(8)) ^ d[2]
    else:
        df = (
            apply_cols(d[0], crc32_zero_cols(24))
            ^ apply_cols(d[1], crc32_zero_cols(16))
            ^ apply_cols(d[2], crc32_zero_cols(8))
            ^ d[3]
        )
    if r == 0:
        return df
    tail_w = words[q] if q < 4 else 0
    dt = apply_cols(tail_w, crc32_data_cols(r))
    return apply_cols(df, crc32_zero_cols(r)) ^ dt


def crc32_columns(nbytes: int) -> tuple[list[int], list[int]]:
    return crc32_zero_cols(nbytes), crc32_data_cols(nbytes)


def mask96(state: list[int], data: list[int], out_bit: int) -> int:
    mask = 0
    for bit, col in enumerate(state):
        if (col >> out_bit) & 1:
            mask |= 1 << (64 + bit)
    for bit, col in enumerate(data):
        if (col >> out_bit) & 1:
            mask |= 1 << bit
    return mask


def crc16_wire(data: list[int]) -> int:
    return (~step_bytes(0xFFFF, data, POLY16, 16)) & 0xFFFF


def crc16_terms() -> tuple[list[int], list[int]]:
    """Per output bit: data mask and the affine constant after invert."""
    const = step_bytes(0xFFFF, [0, 0, 0, 0], POLY16, 16)
    cols = []
    for bit in range(32):
        raw = [0, 0, 0, 0]
        raw[bit // 8] = 1 << (bit % 8)
        cols.append(step_bytes(0, raw, POLY16, 16))
    masks = []
    xors = []
    for out in range(16):
        mask = 0
        for bit, col in enumerate(cols):
            if (col >> out) & 1:
                mask |= 1 << bit
        masks.append(mask)
        xors.append(((const >> out) & 1) ^ 1)
    return masks, xors


def residue() -> int:
    payload = [0x00]
    crc = step_bytes(0xFFFFFFFF, payload, POLY32, 32)
    wire = (~crc) & 0xFFFFFFFF
    raw = payload + [(wire >> (8 * k)) & 0xFF for k in range(4)]
    return step_bytes(0xFFFFFFFF, raw, POLY32, 32)


def self_check(res: int, c16_masks: list[int], c16_xor: list[int]) -> None:
    if crc16_wire([0x40, 0x08, 0x00, 0xE0]) != 0x06F5:
        raise SystemExit("CRC-16 PG213 vector mismatch")
    rng = random.Random(1)
    for _ in range(30):
        data = [rng.randrange(256) for _ in range(4)]
        word = 0
        for i, byte in enumerate(data):
            word |= byte << (8 * i)
        got = 0
        for out, (mask, bit) in enumerate(zip(c16_masks, c16_xor)):
            if (bin(word & mask).count("1") & 1) ^ bit:
                got |= 1 << out
        if got != crc16_wire(data):
            raise SystemExit("CRC-16 parallel mismatch")
    for nbytes in range(1, 9):
        state, data_cols = crc32_columns(nbytes)
        for _ in range(10):
            crc = rng.randrange(1 << 32)
            block = [rng.randrange(256) for _ in range(nbytes)]
            m = crc << 64
            for i, byte in enumerate(block):
                m |= byte << (8 * i)
            acc = 0
            for out in range(32):
                mask = mask96(state, data_cols, out)
                if bin(m & mask).count("1") & 1:
                    acc |= 1 << out
            exp = step_bytes(crc, block, POLY32, 32)
            if acc != exp:
                raise SystemExit(f"CRC-32 fold{nbytes} mismatch")
    for nbytes in range(0, 33):
        for _ in range(15):
            crc = rng.randrange(1 << 32)
            full = [rng.randrange(256) for _ in range(32)]
            got_z = crc32_zero_py(crc, nbytes)
            got_d = crc32_data32_py(full, nbytes)
            exp = step_bytes(crc, full[:nbytes], POLY32, 32)
            if (got_z ^ got_d) != exp:
                raise SystemExit(
                    f"CRC-32 fold32 mismatch n={nbytes}: got={got_z ^ got_d:#x} exp={exp:#x}"
                )
    if res != 0xDEBB20E3:
        raise SystemExit(f"unexpected residue {res:#x}")


def emit_z_fn(a, name: str, nbytes: int) -> None:
    cols = crc32_zero_cols(nbytes)
    a(f"function automatic logic [31:0] {name}(input logic [31:0] crc_in);")
    a("  logic [31:0] crc;")
    for out in range(32):
        mask = mask_from_cols(cols, out)
        a(f"  crc[{out:2d}] = ^(crc_in & 32'h{mask:08X});")
    a("  return crc;")
    a("endfunction")
    a("")


def emit() -> None:
    res = residue()
    c16_masks, c16_xor = crc16_terms()
    self_check(res, c16_masks, c16_xor)
    lines: list[str] = []
    a = lines.append
    a("// Copyright 2026 Rivet contributors")
    a("// SPDX-License-Identifier: Apache-2.0")
    a("//")
    a("// Parallel reflected CRC folds. Generated by scripts/gen_crc_fold.py.")
    a("// Included from rivet_pkg. Do not edit the masks by hand.")
    a("//")
    a("// DLLP CRC-16: poly 100Bh, seed FFFFh, LSB of byte0 first, then invert.")
    a("// LCRC-32: poly 04C11DB7, seed FFFF_FFFF, same bit order. The residue is")
    a("// the LFSR state after a good frame (Seq# + TLP + wire LCRC), which is")
    a("// the complement of the CRC-32 check value 2144DF1Ch.")
    a("")
    a("localparam logic [31:0] RIVET_LCRC32_RESIDUE = 32'hDEBB_20E3;")
    a("")
    a("function automatic logic [15:0] rivet_dllp_crc16_par(")
    a("    input logic [31:0] data);")
    a("  logic [15:0] crc;")
    for out, (mask, bit) in enumerate(zip(c16_masks, c16_xor)):
        a(f"  crc[{out:2d}] = ^(data & 32'h{mask:08X}) ^ 1'b{bit};")
    a("  return crc;")
    a("endfunction")
    a("")
    a("function automatic logic [31:0] rivet_crc32_fold(")
    a("    input logic [31:0] crc_in,")
    a("    input logic [63:0] data_in,")
    a("    input logic [3:0]  nbytes);")
    a("  logic [95:0] m;")
    a("  logic [31:0] crc;")
    a("  m   = {crc_in, data_in};")
    a("  crc = crc_in;")
    a("  case (nbytes)")
    for nbytes in range(1, 9):
        state, data_cols = crc32_columns(nbytes)
        a(f"    4'd{nbytes}: begin")
        for out in range(32):
            mask = mask96(state, data_cols, out)
            a(f"      crc[{out:2d}] = ^(m & 96'h{mask:024X});")
        a("    end")
    a("    default: crc = crc_in;")
    a("  endcase")
    a("  return crc;")
    a("endfunction")
    a("")

    for nb in (8, 16, 24, 32):
        emit_z_fn(a, f"rivet_crc32_z{nb}", nb)

    a("function automatic logic [31:0] rivet_crc32_z_tail(")
    a("    input logic [31:0] crc_in,")
    a("    input logic [2:0]  rem);")
    a("  logic [31:0] crc;")
    a("  crc = crc_in;")
    a("  case (rem)")
    for rem in range(1, 8):
        cols = crc32_zero_cols(rem)
        a(f"    3'd{rem}: begin")
        for out in range(32):
            mask = mask_from_cols(cols, out)
            a(f"      crc[{out:2d}] = ^(crc_in & 32'h{mask:08X});")
        a("    end")
    a("    default: crc = crc_in;")
    a("  endcase")
    a("  return crc;")
    a("endfunction")
    a("")

    d8_cols = crc32_data_cols(8)
    a("function automatic logic [31:0] rivet_crc32_d8(input logic [63:0] data_in);")
    a("  logic [31:0] crc;")
    for out in range(32):
        mask = mask_from_cols(d8_cols, out)
        a(f"  crc[{out:2d}] = ^(data_in & 64'h{mask:016X});")
    a("  return crc;")
    a("endfunction")
    a("")

    a("function automatic logic [31:0] rivet_crc32_d_tail(")
    a("    input logic [63:0] data_in,")
    a("    input logic [2:0]  rem);")
    a("  logic [31:0] crc;")
    a("  crc = 32'h0;")
    a("  case (rem)")
    for rem in range(1, 8):
        cols = crc32_data_cols(rem)
        a(f"    3'd{rem}: begin")
        for out in range(32):
            mask = mask_from_cols(cols, out)
            a(f"      crc[{out:2d}] = ^(data_in & 64'h{mask:016X});")
        a("    end")
    a("    default: crc = 32'h0;")
    a("  endcase")
    a("  return crc;")
    a("endfunction")
    a("")

    a("function automatic logic [31:0] rivet_crc32_zero32(")
    a("    input logic [31:0] crc_in,")
    a("    input logic [5:0]  nbytes);")
    a("  logic [31:0] zq;")
    a("  case (nbytes[5:3])")
    a("    3'd1:    zq = rivet_crc32_z8(crc_in);")
    a("    3'd2:    zq = rivet_crc32_z16(crc_in);")
    a("    3'd3:    zq = rivet_crc32_z24(crc_in);")
    a("    3'd4:    zq = rivet_crc32_z32(crc_in);")
    a("    default: zq = crc_in;")
    a("  endcase")
    a("  return rivet_crc32_z_tail(zq, nbytes[2:0]);")
    a("endfunction")
    a("")

    a("function automatic logic [31:0] rivet_crc32_data32(")
    a("    input logic [255:0] data_in,")
    a("    input logic [5:0]   nbytes);")
    a("  logic [31:0] d0, d1, d2, d3, df, dt;")
    a("  logic [63:0] tail_w;")
    a("  d0 = rivet_crc32_d8(data_in[63:0]);")
    a("  d1 = rivet_crc32_d8(data_in[127:64]);")
    a("  d2 = rivet_crc32_d8(data_in[191:128]);")
    a("  d3 = rivet_crc32_d8(data_in[255:192]);")
    a("  case (nbytes[5:3])")
    a("    3'd1:    df = d0;")
    a("    3'd2:    df = rivet_crc32_z8(d0) ^ d1;")
    a("    3'd3:    df = rivet_crc32_z16(d0) ^ rivet_crc32_z8(d1) ^ d2;")
    a("    3'd4:    df = rivet_crc32_z24(d0) ^ rivet_crc32_z16(d1) ^ rivet_crc32_z8(d2) ^ d3;")
    a("    default: df = 32'h0;")
    a("  endcase")
    a("  case (nbytes[4:3])")
    a("    2'd0:    tail_w = data_in[63:0];")
    a("    2'd1:    tail_w = data_in[127:64];")
    a("    2'd2:    tail_w = data_in[191:128];")
    a("    default: tail_w = data_in[255:192];")
    a("  endcase")
    a("  dt = rivet_crc32_d_tail(tail_w, nbytes[2:0]);")
    a("  return rivet_crc32_z_tail(df, nbytes[2:0]) ^ dt;")
    a("endfunction")
    a("")

    a("function automatic logic [31:0] rivet_crc32_fold32(")
    a("    input logic [31:0]  crc_in,")
    a("    input logic [255:0] data_in,")
    a("    input logic [5:0]   nbytes);")
    a("  logic [31:0] d0, d1, d2, d3, df, zq, mid, dt;")
    a("  logic [63:0] tail_w;")
    a("  d0 = rivet_crc32_d8(data_in[63:0]);")
    a("  d1 = rivet_crc32_d8(data_in[127:64]);")
    a("  d2 = rivet_crc32_d8(data_in[191:128]);")
    a("  d3 = rivet_crc32_d8(data_in[255:192]);")
    a("  case (nbytes[5:3])")
    a("    3'd1: begin")
    a("      zq = rivet_crc32_z8(crc_in);")
    a("      df = d0;")
    a("    end")
    a("    3'd2: begin")
    a("      zq = rivet_crc32_z16(crc_in);")
    a("      df = rivet_crc32_z8(d0) ^ d1;")
    a("    end")
    a("    3'd3: begin")
    a("      zq = rivet_crc32_z24(crc_in);")
    a("      df = rivet_crc32_z16(d0) ^ rivet_crc32_z8(d1) ^ d2;")
    a("    end")
    a("    3'd4: begin")
    a("      zq = rivet_crc32_z32(crc_in);")
    a("      df = rivet_crc32_z24(d0) ^ rivet_crc32_z16(d1) ^ rivet_crc32_z8(d2) ^ d3;")
    a("    end")
    a("    default: begin")
    a("      zq = crc_in;")
    a("      df = 32'h0;")
    a("    end")
    a("  endcase")
    a("  case (nbytes[4:3])")
    a("    2'd0:    tail_w = data_in[63:0];")
    a("    2'd1:    tail_w = data_in[127:64];")
    a("    2'd2:    tail_w = data_in[191:128];")
    a("    default: tail_w = data_in[255:192];")
    a("  endcase")
    a("  mid = zq ^ df;")
    a("  dt  = rivet_crc32_d_tail(tail_w, nbytes[2:0]);")
    a("  return rivet_crc32_z_tail(mid, nbytes[2:0]) ^ dt;")
    a("endfunction")
    a("")

    text = "\n".join(lines)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUT} residue={res:#010x}")


if __name__ == "__main__":
    emit()
