"""A measuring session on one guitar channel: plays the Bypassed tone, edits it without ever saving,
and puts the channel's tone and the volumes back at the end."""
import time, contextlib, struct
from bandbox import BandBox, SLOTS
from audio import record, level, bands, crest, steadiness, USB

BYPASSED = 27
LIMIT = -3.0 if USB else -26.0   # dBFS at the input: louder than this and the session turns the channel down


class Session:
    def __init__(self, ch=3):
        self.b, self.ch = BandBox(), ch
        self.tone = self.b.tone(ch)
        self.master = self.b.ask(0x3405, [0, 0], 0x3406)[2]
        self.volume = self.b.ask(0x3405, [ch, 2], 0x3406)[2]
        self.pickup = self.b.ask(0x3402, [ch], 0x3403)[1]
        self.blocks = {}
        # Over USB the speaker is silent meanwhile: output to the computer, direct monitor off (the DI).
        self.output, self.monitor = self.b.read(0x3180)[0], self.b.read(0x3187)[0]
        if USB: self.b.set(0x3180, [2]); self.b.set(0x3187, [0])

    def reset(self):
        """Bypassed, as saved: every block off."""
        self.b.select(self.ch, BYPASSED)
        self.b.discard(self.ch, BYPASSED)
        self.blocks = {s: dict(v, params=dict(v["params"])) for s, v in self.b.details(BYPASSED)["blocks"].items()}
        time.sleep(0.3)

    def set(self, slot, model=None, on=None, **params):
        """One block: its model (the speaker answers with the model's defaults), on or off, knobs by id (p0=…)."""
        s = SLOTS.index(slot); blk = self.blocks[s]
        if model is not None and model != blk["model"]:
            v = self.b.model(self.ch, s, model)
            blk["model"] = model
            if v and len(v) >= 8 and len(v) >= 8 + 5 * v[7]:
                k = v[7]; blk["params"] = {v[8 + 5 * j]: struct.unpack("<f", v[9 + 5 * j:13 + 5 * j])[0] for j in range(k)}
        for name, value in params.items():
            self.b.param(self.ch, s, blk["model"], int(name[1:]), float(value)); blk["params"][int(name[1:])] = float(value)
        if on is not None and on != blk["on"]:
            self.b.bypass(self.ch, s, blk["model"], on, blk["params"]); blk["on"] = on

    def volumes(self, channel=None, master=None):
        if channel is not None: self.b.set(0x3406, [self.ch, 2, channel])
        if master is not None: self.b.set(0x3406, [0, 0, master])

    def measure(self, seconds=2.0, settle=0.35):
        """A recording of what plays now."""
        time.sleep(settle)
        x = record(seconds)
        if level(x) > LIMIT:
            self.volumes(channel=0)
            raise RuntimeError("too loud (%.1f dBFS): channel turned down" % level(x))
        return x

    def level(self, **kw):
        return level(self.measure(**kw))

    def close(self):
        self.b.discard(self.ch, BYPASSED)
        self.b.set(0x3403, [self.ch, self.pickup])
        self.volumes(self.volume, self.master)
        if self.tone: self.b.select(self.ch, self.tone)
        if USB: self.b.set(0x3187, [self.monitor]); self.b.set(0x3180, [self.output])


@contextlib.contextmanager
def session(ch=3):
    s = Session(ch)
    try:
        s.reset(); yield s
    finally:
        s.close()
