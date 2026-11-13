"""Checks Match amps on the speaker: for the player's slot tones and a set of game rigs, sets the channel to
what the slot has and then to what the match makes of it, each with the test signal at the level the tables
take a guitar to arrive at, and measures both. They should come out equally loud.

    BENCH_INPUT="JBL BandBox Trio" verify.py SLOT_TONE_IDS…     (Clean, Crunch, Heavy, Lead: e.g. 1 15 22 17)

Needs build/match-cli (Stagehand's own matching code; build it with build-match-cli.sh). The test signal
uses the compressor and the Precision Drive, so what those two do in a tone is in the signal's level, as the
tables have it, and not played."""
import json, subprocess, sys, os
from rig import session, SLOTS
from audio import level
from measure import Bench

HERE = os.path.dirname(os.path.abspath(__file__))
RIGS = [  # category, the game's amp, its gain, drive, cab, a pedal
    ("Clean", "Amp_TW22", 25, 0.15, "Cab_TW112C_57_Cone", None),
    ("Clean", "Amp_CS90", 40, 0.10, "Cab_CS212C_57_Cone", None),
    ("Clean", "Amp_MarshallJTM45", 20, 0.20, "Cab_Marshall1960TV_57_Cone", None),
    ("Crunch", "Amp_MarshallPlexi", 60, 0.50, "Cab_Marshall1960a_57_Cone", None),
    ("Crunch", "Amp_EN30", 70, 0.45, "Cab_EN212C_57_Cone", None),
    ("Crunch", "Amp_TW40", 80, 0.55, "Cab_TW410C_57_Cone", "Pedal_GermaniumDrive"),
    ("Heavy", "Amp_CA100", 75, 0.90, "Cab_CA412C_57_Cone", None),
    ("Heavy", "Amp_MarshallJCM800", 85, 0.80, "Cab_Marshall1960a_57_Cone", "Pedal_SuperDrive"),
    ("Heavy", "Amp_HG180", 90, 0.95, "Cab_HG2120C_57_Cone", None),
    ("Lead", "Amp_MarshallDSL100H", 85, 0.85, "Cab_GB412CMKIII_57_Cone", None),
    ("Lead", "Amp_CA85", 70, 0.75, "Cab_CA412C_Ribbon_Edge", None),
]
CATEGORIES = ["Clean", "Crunch", "Heavy", "Lead"]


def model_input(blocks):
    """What the tables take to reach the amp, as GearMatch.input: dB around the test signal."""
    cal = dict(guitar=8.0, drive=[(0, 3.6), (20, 9.3), (40, 14.2), (60, 23.2), (70, 28.8), (80, 34.2), (90, 39.3), (100, 44.0)],
               lvl=[(20, -13.8), (30, -10.2), (40, -7.6), (50, -5.8), (60, -4.3), (70, -3.0), (80, -1.5), (90, -0.5), (100, 0.0)])
    def at(points, x):
        for (a, b), (c, d) in zip(points, points[1:]):
            if x <= c: return b + (d - b) * (x - a) / (c - a)
        return points[-1][1]
    u = cal["guitar"]
    comp, dist = blocks[1], blocks[2]
    if comp["on"]: u += comp["params"].get("4", 0) * 0.18
    if dist["on"] and dist["model"] == 4:
        u += at(cal["drive"], dist["params"].get("0", 44)) + at(cal["lvl"], dist["params"].get("2", 100)) - (100 - dist["params"].get("1", 51)) * 0.06
    return u


def play(bench, blocks, u):
    """The amp and cab of `blocks` on the channel, with the test signal at `u` dB (-13.8 to 18)."""
    s = bench.s
    amp, cab = blocks[3], blocks[4]
    s.set("amp", amp["model"], amp["on"], **{"p" + k: v for k, v in amp["params"].items()})
    s.set("cab", cab["model"], cab["on"])
    u = min(max(u, -13.8), 18.0)
    if u >= 0: bench.source(100, boost=u / 0.18)
    else: bench.source(max(20, 100 + u * 80 / 13.8))     # roughly; only the template of a very quiet tone gets here
    return bench.read("verify")


if __name__ == "__main__":
    slots = [int(x) for x in sys.argv[1:5]]
    with session() as s, open(os.path.join(HERE, "data", "verify.jsonl"), "a") as out:
        bench = Bench(s, out)
        templates = {c: s.b.details(t) for c, t in zip(CATEGORIES, slots)}
        def as_json(d):
            return {"name": d["name"], "blocks": [dict(slot=k, model=b["model"], on=b["on"], params={str(p): v for p, v in b["params"].items()})
                                                 for k, b in sorted(d["blocks"].items())]}
        tones = []
        for i, (cat, amp, gain, drive, cab, pedal) in enumerate(RIGS):
            rig = {"Amp": {"gear": amp, "knobs": {"Gain": gain}}, "Cabinet": {"gear": cab, "knobs": {}}}
            if pedal: rig["PrePedal1"] = {"gear": pedal, "knobs": {"Gain": 50, "Tone": 50}}
            tones.append({"key": "%s %.2f" % (amp, drive), "category": cat, "drive": drive, "rig": rig, "effects": {}})
        results = []
        for chunk in range(0, len(tones), 5):     # a message holds five tones
            part = tones[chunk:chunk + 5]
            job = {"message": {"v": 2, "kind": "song-tones", "tones": part}, "templates": [as_json(templates[t["category"]]) for t in part]}
            results += json.loads(subprocess.run([os.path.join(HERE, "..", "Stagehand", "build", "match-cli")], input=json.dumps(job),
                                                 capture_output=True, text=True, check=True).stdout)
        worst = 0
        for r in results:
            s.reset(); bench.vol = 8
            was = play(bench, r["was"], model_input(r["was"]))
            now = play(bench, r["matched"], model_input(r["matched"]))
            diff = now - was
            worst = max(worst, abs(diff))
            print("%-28s on %-16s  slot %6.1f  match %6.1f  %+5.1f dB   (tables %+.1f)   %s" % (
                r["key"], r["template"], was, now, diff, (r["level_matched"] or 0) - (r["level_was"] or 0), r["note"].split("→")[-1].strip()), flush=True)
        print("worst %.1f dB" % worst)
