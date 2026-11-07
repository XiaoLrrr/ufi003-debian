#!/usr/bin/env python3
"""
Merge adjacent tz (512KB) + tzbak (512KB) partitions into a 1MB tz partition
in the stock UFI003 GPT so 64-bit tz.mbn (591.5KB) fits without altering any
other partition number, LBA, or PARTUUID.
"""
import struct, sys, zlib

def patch_gpt(head_in, tail_in, head_out, tail_out):
    head = bytearray(open(head_in, "rb").read())
    tail = bytearray(open(tail_in, "rb").read())
    hdr = head[512:1024]
    magic, rev, hdr_size, hdr_crc, rsvd, cur_lba, bak_lba, first_u, last_u = struct.unpack("<8sIIIIQQQQ", hdr[:56])
    part_lba, num_parts, entry_sz, parts_crc = struct.unpack("<QIII", hdr[72:92])
    entries = bytearray(head[1024:1024 + num_parts * entry_sz])

    # Entry 7 is tz (270336..271359), Entry 8 is tzbak (271360..272383)
    struct.pack_into("<QQ", entries, 7*128 + 32, 270336, 272382)
    struct.pack_into("<QQ", entries, 8*128 + 32, 272383, 272383)

    new_parts_crc = zlib.crc32(entries) & 0xffffffff
    head[1024:1024 + len(entries)] = entries
    struct.pack_into("<I", head, 512 + 88, new_parts_crc)
    struct.pack_into("<I", head, 512 + 16, 0)
    struct.pack_into("<I", head, 512 + 16, zlib.crc32(head[512:512+hdr_size]) & 0xffffffff)

    tail[0:len(entries)] = entries
    t_hdr_off = len(tail) - 512
    struct.pack_into("<I", tail, t_hdr_off + 88, new_parts_crc)
    struct.pack_into("<I", tail, t_hdr_off + 16, 0)
    struct.pack_into("<I", tail, t_hdr_off + 16, zlib.crc32(tail[t_hdr_off:t_hdr_off+hdr_size]) & 0xffffffff)

    open(head_out, "wb").write(head)
    open(tail_out, "wb").write(tail)
    print(f"Written {head_out} and {tail_out}")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <gpt-head.bin> <gpt-tail.bin> <gpt-head-tz1m.bin> <gpt-tail-tz1m.bin>")
        sys.exit(1)
    patch_gpt(*sys.argv[1:5])
