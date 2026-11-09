#!/usr/bin/env python3
"""Génère tous les sons du jeu (pas, ambiances, tâches, capacités, interface, musique).

Tout est synthétisé ici, sans échantillon externe : les fichiers produits sont libres de droits.
Usage : python3 tools/gen_audio.py   (nécessite numpy et ffmpeg)
Sortie : assets/audio/*.ogg
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(1013)


# ------------------------------------------------------------------ outils

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def band(x, lo, hi):
    """Filtre passe-bande par FFT (rapide, sans dépendance)."""
    n = len(x)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    mask = np.ones_like(freqs)
    if lo:
        mask *= 1 / (1 + (lo / np.maximum(freqs, 1)) ** 4)
    if hi:
        mask *= 1 / (1 + (freqs / hi) ** 4)
    return np.fft.irfft(f * mask, n)


def env(n, a, d, sustain=0.0, curve=4.0):
    """Enveloppe attaque / décroissance exponentielle, en secondes."""
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), np.exp(-(t - a) * curve / max(d, 1e-4)))
    return np.maximum(e, sustain * (t < a + d))


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def place(buf, snd, at):
    i = int(at * SR)
    j = min(len(buf), i + len(snd))
    if i < len(buf):
        buf[i:j] += snd[: j - i]


def loopify(x, fade=0.5):
    """Rend une boucle sans couture : la fin se fond dans le début."""
    n = int(fade * SR)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    w = np.linspace(0, 1, n)
    return np.concatenate([tail * (1 - w) + head * w, body])


def tone(freq, dur, harmonics=(1.0,), detune=0.0):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for k, amp in enumerate(harmonics, start=1):
        out += amp * np.sin(2 * np.pi * freq * k * (1 + detune * (k - 1)) * t)
    return out


def save(name, x, peak=0.8):
    os.makedirs(OUT, exist_ok=True)
    x = norm(x, peak)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
    os.remove(path)


# ------------------------------------------------------------------ pas

def footstep(kind, i):
    d = 0.22
    n = int(d * SR)
    x = noise(d)
    if kind == "concrete":
        s = band(x, 120, 1800) * env(n, 0.002, 0.07)
        s += 0.5 * band(noise(d), 60, 300) * env(n, 0.001, 0.04)
    elif kind == "wood":
        s = band(x, 150, 1200) * env(n, 0.002, 0.05)
        s += 0.8 * tone(140 + 15 * i, d, (1, 0.4)) * env(n, 0.001, 0.06)
    elif kind == "metal":
        s = band(x, 400, 5000) * env(n, 0.001, 0.05)
        ring = sum(tone(f * (1 + 0.03 * i), d) for f in (520, 1290, 2210)) * env(n, 0.001, 0.12)
        s += 0.35 * ring
    else:  # carrelage
        s = band(x, 800, 7000) * env(n, 0.001, 0.025)
        s += 0.4 * tone(900 + 40 * i, d) * env(n, 0.001, 0.03)
    return s * (0.85 + 0.3 * rng.random())


# ------------------------------------------------------------------ ambiances

def amb_refectoire():
    d = 12
    t = t_axis(d)
    x = 0.4 * band(noise(d), 40, 220) + 0.15 * np.sin(2 * np.pi * 50 * t)
    for k in range(10):  # vaisselle au loin
        at = rng.uniform(0.5, d - 0.5)
        n = int(0.3 * SR)
        place(x, 0.12 * tone(rng.uniform(1800, 3200), 0.3, (1, 0.5, 0.2)) * env(n, 0.001, 0.15), at)
    return loopify(x)


def amb_dortoir():
    d = 12
    x = 0.35 * band(noise(d), 80, 600)
    for k in range(4):  # craquements
        at = rng.uniform(0.5, d - 0.6)
        n = int(0.5 * SR)
        place(x, 0.25 * band(noise(0.5), 200, 900) * env(n, 0.05, 0.3) * (1 + np.sin(np.linspace(0, 30, n))), at)
    return loopify(x)


def amb_atelier():
    d = 12
    t = t_axis(d)
    x = 0.5 * band(noise(d), 30, 160) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t))
    x += 0.12 * np.sin(2 * np.pi * 73 * t) + 0.06 * np.sin(2 * np.pi * 146 * t)
    for k in range(int(d / 1.5)):  # piston régulier
        n = int(0.25 * SR)
        place(x, 0.25 * band(noise(0.25), 200, 2500) * env(n, 0.001, 0.08), k * 1.5)
    return loopify(x)


def amb_infirmerie():
    d = 12
    t = t_axis(d)
    x = 0.08 * (np.sin(2 * np.pi * 100 * t) + 0.5 * np.sin(2 * np.pi * 200 * t) + 0.3 * np.sin(2 * np.pi * 300 * t))
    x += 0.2 * band(noise(d), 100, 900)
    for k in range(int(d / 2)):  # bip d'appareil
        n = int(0.12 * SR)
        place(x, 0.15 * tone(1320, 0.12) * env(n, 0.005, 0.1, 0.6), k * 2 + 0.3)
    return loopify(x)


def amb_cave():
    d = 14
    x = 0.25 * band(noise(d), 30, 300)
    for k in range(9):  # gouttes
        at = rng.uniform(0.3, d - 0.5)
        n = int(0.4 * SR)
        f = rng.uniform(900, 1700)
        tt = np.arange(n) / SR
        drop = np.sin(2 * np.pi * (f + 900 * np.exp(-tt * 30)) * tt) * env(n, 0.001, 0.12)
        place(x, 0.3 * drop, at)
    return loopify(x)


# ------------------------------------------------------------------ tâches (boucles courtes)

def rhythmic(period, hit, d=6.0, jitter=0.03):
    x = np.zeros(int(d * SR))
    at = 0.05
    while at < d - 0.4:
        place(x, hit(), at + rng.uniform(-jitter, jitter))
        at += period
    return loopify(x, 0.1)


def task_sounds():
    s = {}
    s["task_stir"] = loopify(0.6 * band(noise(6), 200, 1500) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.2 * t_axis(6))) ** 2, 0.3)
    s["task_chop"] = rhythmic(0.45, lambda: band(noise(0.2), 300, 3000) * env(int(0.2 * SR), 0.001, 0.04)
                              + 0.5 * tone(220, 0.2) * env(int(0.2 * SR), 0.001, 0.05))
    s["task_water"] = loopify(band(noise(6), 500, 6000) * (0.8 + 0.2 * np.sin(2 * np.pi * 7 * t_axis(6))), 0.3)
    s["task_hammer"] = rhythmic(0.9, lambda: (band(noise(0.5), 500, 6000) * env(int(0.5 * SR), 0.001, 0.05)
                                + 0.6 * sum(tone(f, 0.5) for f in (440, 1180, 2650)) * env(int(0.5 * SR), 0.001, 0.25)))
    x = np.zeros(int(6 * SR))
    for k in range(400):  # crépitement de soudure
        at = rng.uniform(0, 5.9)
        place(x, rng.uniform(0.3, 1) * band(noise(0.02), 1500, 9000) * env(int(0.02 * SR), 0.0005, 0.008), at)
    x += 0.2 * band(noise(6), 2000, 8000) + 0.08 * np.sin(2 * np.pi * 120 * t_axis(6))
    s["task_weld"] = loopify(x, 0.2)
    s["task_write"] = rhythmic(0.32, lambda: band(noise(0.25), 1500, 6000) * env(int(0.25 * SR), 0.03, 0.15), jitter=0.08)
    s["task_paper"] = rhythmic(1.1, lambda: band(noise(0.5), 800, 7000) * env(int(0.5 * SR), 0.05, 0.3), jitter=0.2)
    x = np.zeros(int(6 * SR))
    for k in range(60):  # bulles
        at = rng.uniform(0, 5.8)
        n = int(0.08 * SR)
        tt = np.arange(n) / SR
        f = rng.uniform(300, 900)
        place(x, np.sin(2 * np.pi * f * (1 + tt * 8) * tt) * env(n, 0.002, 0.05), at)
    s["task_bubble"] = loopify(x, 0.2)
    s["task_cards"] = rhythmic(0.7, lambda: band(noise(0.08), 2000, 8000) * env(int(0.08 * SR), 0.001, 0.02), jitter=0.2)
    s["task_boiler"] = loopify(0.7 * band(noise(6), 25, 120) + 0.25 * band(noise(6), 3000, 9000), 0.3)
    s["task_glass"] = rhythmic(0.8, lambda: 0.6 * tone(rng.uniform(2200, 3400), 0.4, (1, 0.3)) * env(int(0.4 * SR), 0.001, 0.2), jitter=0.25)
    s["task_sweep"] = rhythmic(0.75, lambda: band(noise(0.5), 1000, 6000) * env(int(0.5 * SR), 0.12, 0.25), jitter=0.05)
    s["task_eat"] = rhythmic(1.4, lambda: 0.5 * tone(rng.uniform(1600, 2400), 0.25, (1, 0.4)) * env(int(0.25 * SR), 0.001, 0.08), jitter=0.4)
    s["task_hum"] = loopify(sum(0.3 * tone(f, 6, (1, 0.3)) for f in (196, 247, 294)) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.33 * t_axis(6))), 0.4)
    return s


# ------------------------------------------------------------------ capacités, interface, récit

def sweep(f0, f1, d, harm=(1, 0.3, 0.1)):
    t = t_axis(d)
    f = f0 * (f1 / f0) ** (t / d)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(a * np.sin(ph * (k + 1)) for k, a in enumerate(harm))


def one_shots():
    s = {}
    n = int(1.2 * SR)
    s["ab_echo"] = sweep(180, 900, 1.2) * env(n, 0.02, 0.9) + 0.3 * band(noise(1.2), 2000, 8000) * env(n, 0.01, 0.4)
    n = int(1.4 * SR)
    s["ab_thread"] = sum(tone(f, 1.4, (1, 0.2)) for f in (660, 990, 1320)) * env(n, 0.05, 1.0) * (1 + 0.3 * np.sin(2 * np.pi * 9 * t_axis(1.4)))
    n = int(0.7 * SR)
    s["ab_mark"] = (tone(1760, 0.7, (1, 0.5)) + 0.6 * tone(2637, 0.7)) * env(n, 0.002, 0.45)
    n = int(1.6 * SR)
    s["ab_confide"] = sum(tone(f, 1.6, (1, 0.4, 0.2)) for f in (293.7, 349.2, 440.0, 587.3)) * env(n, 0.15, 1.2)
    s["ab_ready"] = tone(1046, 0.25, (1, 0.3)) * env(int(0.25 * SR), 0.002, 0.15)
    s["ui_click"] = band(noise(0.06), 1500, 6000) * env(int(0.06 * SR), 0.001, 0.015) + 0.4 * tone(1400, 0.06) * env(int(0.06 * SR), 0.001, 0.02)
    s["ui_open"] = band(noise(0.45), 600, 6000) * env(int(0.45 * SR), 0.04, 0.3)
    n = int(0.9 * SR)
    clue = np.zeros(n)
    place(clue, tone(988, 0.6, (1, 0.3)) * env(int(0.6 * SR), 0.002, 0.4), 0.0)
    place(clue, tone(1319, 0.6, (1, 0.3)) * env(int(0.6 * SR), 0.002, 0.4), 0.12)
    s["ui_clue"] = clue
    s["ui_error"] = tone(196, 0.3, (1, 0.5, 0.3)) * env(int(0.3 * SR), 0.005, 0.2)
    s["ui_unstuck"] = sweep(900, 300, 0.5) * env(int(0.5 * SR), 0.01, 0.4)
    n = int(4 * SR)
    s["sting_body"] = (sum(tone(f, 4, (1, 0.5, 0.3)) for f in (73.4, 77.8, 110.0)) * env(n, 0.05, 3.5)
                       + 0.4 * band(noise(4), 30, 200) * env(n, 0.01, 2.5))
    n = int(3 * SR)
    s["sting_night"] = sum(tone(f, 3, (1, 0.3)) for f in (146.8, 174.6, 220.0)) * env(n, 0.6, 2.4)
    s["door_swish"] = band(noise(0.5), 300, 3000) * env(int(0.5 * SR), 0.15, 0.3)
    return s


# ------------------------------------------------------------------ musique

def music():
    """Boucle de 64 s : nappe grave en ré mineur, notes de « piano » clairsemées."""
    d = 64.0
    t = t_axis(d)
    x = np.zeros_like(t)
    chords = [(73.4, 110.0, 146.8), (58.3, 87.3, 116.5), (65.4, 98.0, 130.8), (55.0, 82.4, 110.0)]
    seg = d / len(chords)
    for i, ch in enumerate(chords):
        n = int(seg * SR)
        tt = np.arange(n) / SR
        e = np.minimum(1, tt / 3) * np.minimum(1, (seg - tt) / 3)
        pad = sum(np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * 2.003 * tt) for f in ch)
        pad *= 0.5 + 0.5 * np.sin(2 * np.pi * 0.1 * tt + i)
        x[int(i * seg * SR): int(i * seg * SR) + n] += 0.25 * pad * e
    scale = [293.7, 349.2, 392.0, 440.0, 523.3, 587.3, 698.5]
    at = 1.0
    while at < d - 4:
        f = scale[rng.integers(len(scale))]
        n = int(3.5 * SR)
        note = tone(f, 3.5, (1, 0.45, 0.2, 0.1), detune=0.001) * env(n, 0.005, 2.2)
        place(x, 0.35 * note, at)
        at += rng.choice([2.0, 3.0, 4.0, 6.0])
    x += 0.05 * band(noise(d), 200, 2000)
    return loopify(x, 2.0)


def main():
    for kind in ("concrete", "wood", "metal", "tile"):
        for i in range(4):
            save(f"step_{kind}_{i + 1}", footstep(kind, i), 0.7)
    save("amb_refectoire", amb_refectoire(), 0.5)
    save("amb_dortoir", amb_dortoir(), 0.4)
    save("amb_atelier", amb_atelier(), 0.55)
    save("amb_infirmerie", amb_infirmerie(), 0.4)
    save("amb_cave", amb_cave(), 0.4)
    for name, x in task_sounds().items():
        save(name, x, 0.6)
    for name, x in one_shots().items():
        save(name, x, 0.8)
    save("music_bunker", music(), 0.6)
    print("ok", len(os.listdir(OUT)), "fichiers")


if __name__ == "__main__":
    main()
