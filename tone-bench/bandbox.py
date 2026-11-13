"""Talks to the speaker through ToneBench.app (tone-bench.swift): the control channel as Python calls."""
import socket, struct, time

SLOTS = ["gate", "comp", "dist", "amp", "cab", "fx", "delay", "reverb"]


class BandBox:
    def __init__(self, port=47800):
        self.s = socket.create_connection(("127.0.0.1", port))
        self.f = self.s.makefile("rw", newline="\n")

    def cmd(self, line):
        self.f.write(line + "\n"); self.f.flush()
        return self.f.readline().strip()

    def mark(self): return int(self.cmd("mark"))

    def set(self, pid, value):
        r = self.cmd("set %04x %s" % (pid, bytes(value).hex()))
        if r != "ok": raise IOError("set %04x: %s" % (pid, r))

    def get(self, *ids):
        m = self.mark()
        self.cmd("get " + ",".join("%04x" % i for i in ids))
        return m

    def wait(self, pid, mark, prefix=b"", ms=2500):
        r = self.cmd("wait %04x %d %d %s" % (pid, mark, ms, bytes(prefix).hex()))
        return None if r == "none" else bytes.fromhex(r.split(" ")[2]) if len(r.split(" ")) > 2 else b""

    def recv(self, mark):
        self.f.write("recv %d\n" % mark); self.f.flush()
        out = []
        while True:
            line = self.f.readline().strip()
            if line == ".": return out
            p = line.split(" ")
            out.append((int(p[1], 16), bytes.fromhex(p[2]) if len(p) > 2 else b""))

    def ask(self, query, value, answer, prefix=None):
        m = self.mark()
        self.set(query, value)
        return self.wait(answer, m, bytes(value) if prefix is None else prefix)

    def read(self, pid):
        return self.wait(pid, self.get(pid))

    # Tones
    def tone(self, ch): 
        v = self.ask(0x3441, [ch], 0x3442)
        return v[1] if v else None

    def select(self, ch, tone):
        m = self.mark()
        self.set(0x3442, [ch, tone])
        return self.wait(0x3442, m, bytes([ch, tone]), 1500)

    def details(self, tone):
        v = self.ask(0x3443, [tone], 0x3444)
        if not v: return None
        n = v[2]; name = v[3:3 + n].decode(errors="replace"); i = 3 + n; cnt = v[i]; i += 1
        blocks = {}
        for _ in range(cnt):
            slot, model, byp, k = v[i], v[i + 1] | v[i + 2] << 8, v[i + 3], v[i + 4]
            params = {v[i + 5 + 5 * j]: struct.unpack("<f", v[i + 6 + 5 * j:i + 10 + 5 * j])[0] for j in range(k)}
            blocks[slot] = {"model": model, "on": byp == 0, "params": params}
            i += 5 + 5 * k
        return {"id": v[0], "cat": v[1], "name": name, "blocks": blocks}

    def library(self):
        v = self.read(0x3440) or b""
        out, i = [], 0
        while i + 3 <= len(v) and i + 3 + v[i + 2] <= len(v):
            out.append((v[i], v[i + 1], v[i + 3:i + 3 + v[i + 2]].decode(errors="replace"))); i += 3 + v[i + 2]
        return out

    # Edits to the tone the channel plays (0x3445)
    def model(self, ch, slot, model):
        op = 3 if slot in (3, 4) and model & 0xFF in (6, 8) else 2
        m = self.mark()
        self.set(0x3445, [ch, 0, op, slot, model & 0xFF, model >> 8, 0xFF, 0])
        return self.wait(0x3445, m, bytes([ch, 0, 0, slot, model & 0xFF, model >> 8]), ms=1500)   # op 00: the model's defaults

    def param(self, ch, slot, model, param, value):
        self.set(0x3445, bytes([ch, 0, 4, slot, model & 0xFF, model >> 8, 0xFF, 1, param]) + struct.pack("<f", value))

    def bypass(self, ch, slot, model, on, params=None):
        body = b"".join(bytes([k]) + struct.pack("<f", x) for k, x in sorted((params or {}).items()))
        self.set(0x3445, bytes([ch, 0, 1, slot, model & 0xFF, model >> 8, 0 if on else 1, len(params or {})]) + body)

    def action(self, ch, op, tone, target=0xFF, cat=0xFF, name=""):
        m = self.mark()
        n = name.encode()
        self.set(0x3446, bytes([ch, op, tone, target, cat, len(n)]) + n)
        return self.wait(0x3446, m, bytes([ch, op]))

    def discard(self, ch, tone): return self.action(ch, 8, tone)
