"""Measures the speaker's amps, cabs and knobs with what a guitar channel has at hand: the guitar's own
idle noise, raised by the Precision Drive at full until it is a hot, steady signal that saturates an amp
as playing does. Writes one JSON line per reading to data/NAME.jsonl; analyse.py reads them.

    measure.py NAME [amps] [volume] [cabs] [eq] [steps]      (all of them if none is named)

A guitar (or just its cable) in channel 3, the room quiet-ish; the speaker hisses at a moderate level.
Each reading is the level at the input (BENCH_INPUT, the Mac's microphone by default) in the quiet
fifth of its frames, so other sounds in the room don't count. The channel's volume is the range switch:
turned down for a loud setting and up for a quiet one, and noted with the reading."""
import json, sys, time
from rig import session, SLOTS
from audio import level, bands, steadiness, USB

AMPS = ["American Clean", "Jazz Sound", "Yellow Tweed", "UK Crunch", "British Lead", "Vintage Drive",
        "American Gain Stack", "US Metal", "Bass Amp"]
CABS = ["Champion 1x8", "Voks 2x12", "TR65 2x12", "UK 2550 2x12", "BM59 4x10", "Tanger 4x12", "UK 1960 4x12",
        "6505 4x12", "Mebo 4x12", "M Bass 2x10", "A Bass 8x10", "JC120 2x12"]
REF_AMP, REF_CAB = 3, 6             # UK Crunch into UK 1960 4x12
LOUD, QUIET = (-20.0, -80.0) if USB else (-34.0, -58.0)   # the window the input's level is kept in


class Bench:
    def __init__(self, s, out):
        self.s, self.out, self.vol = s, out, 8 if USB else 5

    def source(self, level=100, on=True, boost=None):
        """The test signal: the Precision Drive at full, its Level the signal's level. `boost` is the
        compressor's Output ahead of it, 0-100 for 0 to 18 dB more (ratio 1, so it only amplifies)."""
        self.s.set("dist", 0x0004, on, p0=100, p1=100, p2=level)
        if boost is None: self.s.set("comp", on=False)
        else: self.s.set("comp", on=True, p0=100, p1=1.0, p4=boost)

    # The test signal's levels for `transfer`: (compressor Output or None, Precision Drive Level), about
    # -14 … +18 dB around the plain test signal, 3 to 4 dB apart.
    LEVELS = [(None, 20), (None, 30), (None, 40), (None, 60), (None, 100), (25, 100), (50, 100), (75, 100), (100, 100)]

    def transfer(self):
        """Each guitar amp's output over its input, at five Drives: where it stops following the input, it saturates."""
        self.s.set("amp", on=False); self.s.set("cab", on=False)
        for i, (boost, lv) in enumerate(self.LEVELS):
            self.source(lv, boost=boost); self.read("source", step=i)
        self.s.set("cab", on=True)
        for a, name in enumerate(AMPS[:8]):
            self.source(); self.reference()
            self.amp(a, p4=50)
            for d in (0, 25, 50, 75, 100):
                self.s.set("amp", p0=d)
                for i, (boost, lv) in enumerate(self.LEVELS):
                    self.source(lv, boost=boost)
                    self.read("transfer", amp=name, drive=d, step=i)
        self.source()

    def amp(self, i, **knobs):
        self.s.set("amp", i << 8 | 6, True, **knobs)

    def read(self, what, **tags):
        """One reading, with the channel's volume moved until the level is in the window."""
        for _ in range(8):
            self.s.volumes(channel=self.vol)
            x = self.s.measure(1.5)
            l = level(x)
            if steadiness(x) > 1.5: x = self.s.measure(1.5); l = level(x)   # still settling, or a gap in the recording
            if l > LOUD and self.vol > 1: self.vol = max(1, self.vol - 2); continue
            if l < QUIET and self.vol < 20: self.vol = min(20, self.vol + 3); continue
            break
        row = dict(what=what, vol=self.vol, level=round(l, 2), steady=round(steadiness(x), 2), **tags)
        if tags.get("bands"): row["bands"] = [round(float(v), 1) for v in bands(x)]
        self.out.write(json.dumps(row) + "\n"); self.out.flush()
        print(row if "bands" not in row else {k: v for k, v in row.items() if k != "bands"}, flush=True)
        return l

    def reference(self):
        """The same setting again and again through the run, to see the test signal drift."""
        self.amp(REF_AMP, p0=100, p4=50)
        self.s.set("cab", REF_CAB << 8 | 8, True)
        self.source()
        self.read("reference")

    def start(self):
        self.s.volumes(channel=0)
        self.out.write(json.dumps(dict(what="floor", level=round(level(self.s.measure(2.0)), 2))) + "\n")
        self.s.set("cab", REF_CAB << 8 | 8, True)
        self.reference()

    def steps(self):
        """The channel volume's steps, on a loud and on a quiet setting, and the test signal's Level knob."""
        self.reference()
        for v in range(1, 13):
            self.vol = v; self.s.volumes(channel=v)
            x = self.s.measure(1.5)
            self.out.write(json.dumps(dict(what="channel volume", vol=v, level=round(level(x), 2), setting="loud")) + "\n")
            if level(x) > LOUD + 4: break
        self.s.set("amp", p0=0, p4=25)
        for v in range(6, 25, 2):
            self.vol = v; self.s.volumes(channel=v)
            x = self.s.measure(1.5)
            self.out.write(json.dumps(dict(what="channel volume", vol=v, level=round(level(x), 2), setting="quiet")) + "\n")
            if level(x) > LOUD + 4: break
        self.out.flush()
        self.vol = 8 if USB else 5
        # The Level knob, after the pedal and ahead of nothing that distorts: the amp and cab off.
        self.s.set("amp", on=False); self.s.set("cab", on=False)
        for lv in (100, 90, 80, 70, 60, 50, 40, 30, 20):
            self.source(lv); self.read("source level", knob=lv)
        self.s.set("cab", on=True)

    def amps(self):
        """Every amp over its Drive, at Volume 50 and the model's own tone knobs, with the test signal at
        full and 12 steps of its Level knob lower: how far the output follows the input says how saturated it is."""
        for i, name in enumerate(AMPS):
            self.reference()
            self.amp(i, p4=50)
            for src in (100, 60):
                self.source(src)
                for d in range(0, 101, 10):
                    self.s.set("amp", p0=d)
                    self.read("amp", amp=name, drive=d, source=src)

    def volume(self):
        for i in (0, 3, 7):
            self.reference()
            self.amp(i, p0=[32, 0, 0, 65, 0, 0, 0, 100][i])
            self.source()
            for v in range(20, 101, 10):
                self.s.set("amp", p4=v)
                self.read("amp volume", amp=AMPS[i], volume=v)

    def cabs(self):
        self.reference()
        for c, name in enumerate(CABS):
            self.s.set("cab", c << 8 | 8, True)
            self.read("cab", cab=name, bands=True)
        self.s.set("cab", on=False)
        self.read("cab", cab="off", bands=True)
        self.s.set("cab", REF_CAB << 8 | 8, True)

    def eq(self):
        for i in (0, 3, 7):
            self.reference()
            self.amp(i, p0=[32, 0, 0, 65, 0, 0, 0, 100][i], p4=50)
            self.source()
            for knob, name in ((1, "bass"), (2, "mid"), (3, "treble")):
                was = self.s.blocks[3]["params"].get(knob, 50)
                for value in (0, 25, 50, 75, 100):
                    self.s.set("amp", **{"p%d" % knob: value})
                    self.read("amp eq", amp=AMPS[i], knob=name, value=value, bands=True)
                self.s.set("amp", **{"p%d" % knob: was})


if __name__ == "__main__":
    name, parts = sys.argv[1], sys.argv[2:] or ["steps", "amps", "volume", "cabs", "eq"]
    with session() as s, open("data/%s.jsonl" % name, "a") as out:
        bench = Bench(s, out)
        bench.start()
        for part in parts: getattr(bench, part)()
        bench.reference()
