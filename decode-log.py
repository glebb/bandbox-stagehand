#!/usr/bin/env python3
"""Decode a BLEScan listen log (com/0001 <- / com/0002 -> lines) with the
same message decoder as decode-pklg.py.

Usage: python3 -I decode-log.py listen.log [--keep-stream]
By default the repeating tuner feed (0x3106) and keep-alives are collapsed.
"""
import os
import re
import sys


spec_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "decode-pklg.py")
ns = {"__name__": "decode_pklg"}
exec(compile(open(spec_path).read(), spec_path, "exec"), ns)
decode_message = ns["decode_message"]

LINE = re.compile(r"^\[(?P<ts>[\d:.]+)\] (?P<ch>\S+) (?P<dir><-|->) \(\d+B\) (?P<hex>[0-9a-f ]+?)\s+\|")


def main():
    keep = "--keep-stream" in sys.argv
    last, repeats = None, 0
    for raw in open(sys.argv[1]):
        m = LINE.match(raw)
        if not m:
            if "acknowledged" in raw or raw.startswith(("•", "Bluetooth", "SERVICE")) or not raw.strip():
                continue
            print(raw.rstrip())
            continue
        value = bytes.fromhex(m["hex"].replace(" ", ""))
        from_mac = m["dir"] == "->"
        text = decode_message(value, from_mac) or value.hex(" ")
        who = "mac->spk" if from_mac else "spk->mac"
        line = f"{who}  {text}"
        if not keep and "keepalive=-" in text:
            continue
        if not keep and line == last:
            repeats += 1
            continue
        if repeats:
            print(f"{'':14}(… repeated {repeats} more times)")
            repeats = 0
        print(f"{m['ts']}  {line}")
        last = line
    if repeats:
        print(f"{'':14}(… repeated {repeats} more times)")


if __name__ == "__main__":
    main()
