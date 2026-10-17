#!/usr/bin/env python3
"""Decode a PacketLogger .pklg capture into BandBox Trio protocol messages.

Prints every ATT write (phone -> speaker) and notification/indication
(speaker -> phone) whose value starts with the 00 dd framing, decoded into
property records using the table from protocol-notes.md. Other ATT traffic
can be shown with --all.

Usage: python3 -I decode-pklg.py capture.pklg [--all]
"""
import struct
import sys
from datetime import datetime, timezone

PROPS = {
    0x0001: "hello",
    0x000D: "battery%",
    0x3081: "stem?3081",
    0x3082: "stem?3082",
    0x3085: "STEM_AI",
    0x3406: "volume",
    0x3442: "preset",
    0x0002: "keepalive",
    0x0004: "fw_version",
    0x0006: "model_name",
    0x0008: "serial",
    0x0031: "datetime",
    0x3100: "TUNER",
    0x3103: "tuner_ref",
    0x3106: "tuner_feed",
    0x3400: "chan_query",
    0x3401: "chan_info",
    0x3405: "level_query",
    0x3804: "ui_mode?",
    0x3080: "karaoke",
    0x30C0: "pitch_active",
    0x30C1: "pitch_shift",
    0x3443: "tone_details_query",
    0x3444: "tone_details",
    0x3445: "effect_block",
    0x3446: "tone_action",
}

ATT_OPS = {
    0x12: "WriteReq",
    0x52: "WriteCmd",
    0x1B: "Notify",
    0x1D: "Indicate",
    0x13: "WriteRsp",
    0x01: "Error",
}

# PacketLogger record types for ACL data
ACL_SENT, ACL_RECV = 0x02, 0x03


def records(data):
    """Yield (timestamp, type, payload). Detects big- vs little-endian files."""
    def parse(endian):
        out, off = [], 0
        while off + 13 <= len(data):
            (length,) = struct.unpack_from(endian + "I", data, off)
            if length < 9 or off + 4 + length > len(data):
                return None
            secs, usecs = struct.unpack_from(endian + "II", data, off + 4)
            rtype = data[off + 12]
            out.append((secs + usecs / 1e6, rtype, data[off + 13: off + 4 + length]))
            off += 4 + length
        return out if off == len(data) else None

    recs = parse(">") or parse("<")
    if recs is None:
        sys.exit("Could not parse file as PacketLogger .pklg (tried both byte orders).")
    return recs


def acl_to_att(recs):
    """Reassemble L2CAP frames from ACL fragments; yield (ts, direction, att_pdu)."""
    partial = {}  # (dir, conn handle) -> [ts, expected_len, bytes]
    for ts, rtype, p in recs:
        if rtype not in (ACL_SENT, ACL_RECV) or len(p) < 4:
            continue
        direction = "->" if rtype == ACL_SENT else "<-"
        hdr, _acl_len = struct.unpack_from("<HH", p, 0)
        handle, pb = hdr & 0x0FFF, (hdr >> 12) & 0x3
        body = p[4:]
        key = (direction, handle)
        if pb in (0x0, 0x2):  # start of an L2CAP frame
            if len(body) < 4:
                continue
            l2_len, cid = struct.unpack_from("<HH", body, 0)
            partial[key] = [ts, l2_len, cid, bytearray(body[4:])]
        elif pb == 0x1 and key in partial:  # continuation
            partial[key][3] += body
        else:
            continue
        start_ts, l2_len, cid, buf = partial[key]
        if len(buf) >= l2_len:
            del partial[key]
            if cid == 0x0004:  # ATT
                yield start_ts, direction, bytes(buf[:l2_len])


TYPES = {1: "GET", 2: "SET", 3: "EVENT", 4: "ACK"}


def records_str(body):
    parts = []
    while len(body) >= 4:
        pid, vlen = struct.unpack_from("<HH", body, 0)
        val = body[4:4 + vlen]
        parts.append(f"{PROPS.get(pid, f'{pid:#06x}')}={val.hex(' ') or '-'}")
        body = body[4 + vlen:]
    if body:
        parts.append(f"trailing={body.hex(' ')}")
    return "  ".join(parts)


def decode_message(v, from_phone):
    """Decode 00 dd framing by message type, or None if it doesn't fit."""
    if len(v) < 8 or v[0:2] != bytes([0x00, 0xDD]):
        return None
    mtype, ver, _plen = struct.unpack_from("<HHH", v, 2)
    payload = v[8:]
    name = TYPES.get(mtype, f"type{mtype:#06x}")
    if mtype not in TYPES or ver != 1:
        return f"{name} ver={ver} raw={payload.hex(' ')}"
    if from_phone and mtype == 1:  # GET: list of property IDs
        ids = struct.unpack_from(f"<{len(payload) // 2}H", payload, 0)
        return "GET    " + " ".join(PROPS.get(i, f"{i:#06x}") for i in ids)
    if from_phone and mtype == 2:  # SET: property records
        return "SET    " + records_str(payload)
    if from_phone:  # ACK
        return f"{name}    {payload.hex(' ')}"
    status = struct.unpack_from("<H", payload, 0)[0] if len(payload) >= 2 else 0
    st = "" if status == 0 else f" status={status:#06x}"
    label = {1: "GET-reply", 2: "SET-reply", 3: "EVENT"}[mtype]
    return f"{label}{st}  {records_str(payload[2:])}"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    show_all = "--all" in sys.argv
    recs = records(open(sys.argv[1], "rb").read())
    count = 0
    for ts, direction, att in acl_to_att(recs):
        if not att:
            continue
        op = att[0]
        if op not in (0x12, 0x52, 0x1B, 0x1D):
            if show_all:
                print(f"{datetime.fromtimestamp(ts, timezone.utc):%H:%M:%S.%f}"[:-3], direction, ATT_OPS.get(op, f"op{op:#04x}"), att[1:].hex(" "))
            continue
        if len(att) < 3:
            continue
        (att_handle,) = struct.unpack_from("<H", att, 1)
        value = att[3:]
        decoded = decode_message(value, direction == "->")
        if decoded is None and not show_all:
            continue
        stamp = f"{datetime.fromtimestamp(ts, timezone.utc):%H:%M:%S.%f}"[:-3]
        who = "phone->spk" if direction == "->" else "spk->phone"
        print(f"{stamp}  {who}  {decoded or ATT_OPS[op] + ' h=' + hex(att_handle) + ' ' + value.hex(' ')}")
        count += 1
    print(f"\n{count} messages", file=sys.stderr)


if __name__ == "__main__":
    main()
