"""Records the speaker and measures what it plays: level, and level by third-octave band. The input is
BENCH_INPUT: the Mac's microphone by default, or "JBL BandBox Trio" for the speaker's own USB feed (its
first channel is the guitar channel after its tone and its volume, with output to the computer on)."""
import subprocess, os, threading, time
import numpy as np
from scipy.signal import welch

MIC = os.environ.get("BENCH_INPUT", "MacBook Air Microphone")
BANDS = [80 * 2 ** (i / 3) for i in range(22)]   # 80 Hz … 10 kHz


class Recorder:
    """The input, recorded all the time by one ffmpeg, so a measurement doesn't wait for the device to open."""

    def __init__(self, device=None):
        self.p = subprocess.Popen(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "avfoundation", "-i", ":" + (device or MIC),
                                   "-af", "pan=mono|c0=c0", "-ar", "48000", "-f", "s32le", "pipe:1"], stdout=subprocess.PIPE)
        self.lock, self.chunks, self.total = threading.Lock(), [], 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        while True:
            data = self.p.stdout.read(4800 * 4)
            if not data: return
            with self.lock:
                self.chunks.append(np.frombuffer(data, dtype="<i4").astype(np.float64) / 2 ** 31)
                self.total += len(self.chunks[-1])
                while len(self.chunks) > 200: self.chunks.pop(0)

    def take(self, seconds):
        """The next `seconds` of sound, from now."""
        with self.lock: start = self.total
        need = start + int((seconds + 0.25) * 48000)   # a quarter second for what was already on its way
        deadline = time.time() + seconds + 10
        while True:
            with self.lock:
                if self.total >= need:
                    x = np.concatenate(self.chunks)
                    return x[-int(seconds * 48000):]
            if time.time() > deadline or self.p.poll() is not None: raise IOError("the recording stopped")
            time.sleep(0.05)

    def close(self): self.p.terminate()


_recorder = None


def record(seconds):
    """`seconds` of the input from now, as floats at 48 kHz."""
    global _recorder
    if _recorder is None: _recorder = Recorder()
    return _recorder.take(seconds)


def db(x): return 10 * np.log10(np.maximum(x, 1e-20))


def frames(x, lo=300, hi=6000, n=2048):
    """Power between `lo` and `hi` Hz in each frame of `n` samples (half overlapped)."""
    w = np.hanning(n)
    k = np.fft.rfftfreq(n, 1 / 48000)
    keep = (k >= lo) & (k < hi)
    out = []
    for i in range(0, len(x) - n, n // 2):
        s = np.fft.rfft(x[i:i + n] * w)
        out.append((np.abs(s[keep]) ** 2).sum() * 2 / (w ** 2).sum() / n)
    return np.array(out)


def level(x, lo=300, hi=6000):
    """Level in dBFS between `lo` and `hi` Hz, where the speaker plays and the room's rumble and the
    guitar's hum don't. It is the quiet fifth of the 43 ms frames, so a door, a voice or typing on
    the Mac doesn't count: for a steady noise that is within 0.3 dB of the mean."""
    return float(db(np.percentile(frames(x, lo, hi), 20)))


def steadiness(x, lo=300, hi=6000):
    """The median frame over the quiet fifth, dB: about 0.3 for a steady noise, more with other sounds in it."""
    p = frames(x, lo, hi)
    return float(db(np.median(p)) - db(np.percentile(p, 20)))


def bands(x):
    """Level in each third-octave band of BANDS, dBFS."""
    f, p = welch(x, 48000, nperseg=16384)
    return np.array([db(p[(f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))].sum() * (f[1] - f[0])) for c in BANDS])


USB = "BandBox" in MIC


def crest(x): return float(20 * np.log10(np.abs(x).max() / np.sqrt((x ** 2).mean())))
