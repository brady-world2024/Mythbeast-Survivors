"""Render original Mythbeast Survivors cues and backing tracks to mono PCM WAV."""

from argparse import ArgumentParser
from array import array
from math import exp, pi, sin
from pathlib import Path
from random import Random
import sys
import wave

RATE = 22_050
TAU = 2.0 * pi


def frequency(midi_note):
    return 440.0 * 2.0 ** ((midi_note - 69) / 12.0)


def silence(seconds):
    return [0.0] * round(seconds * RATE)


def mix_note(output, start, duration, note, gain, voice="bell", drift=0.0):
    length = min(round(duration * RATE), len(output) - round(start * RATE))
    first = round(start * RATE)
    hz = frequency(note)
    for index in range(length):
        t = index / RATE
        progress = t / duration
        phase = TAU * (hz * t + drift * hz * t * t / (2.0 * duration))
        envelope = min(1.0, t / 0.008, (duration - t) / 0.035)
        if voice == "bell":
            sample = (
                sin(phase) * exp(-3.6 * progress)
                + 0.28 * sin(phase * 2.01) * exp(-6.5 * progress)
                + 0.08 * sin(phase * 3.98) * exp(-12.0 * progress)
            )
        elif voice == "wood":
            sample = (
                sin(phase) * exp(-4.0 * progress)
                + 0.20 * sin(phase * 3.0) * exp(-11.0 * progress)
            )
        else:
            envelope *= min(1.0, t / 0.075, (duration - t) / 0.09)
            sample = 0.86 * sin(phase) + 0.14 * sin(phase * 2.0)
        output[first + index] += gain * envelope * sample


def mix_air(output, start, duration, gain, seed):
    random = Random(seed)
    last = 0.0
    first = round(start * RATE)
    for index in range(min(round(duration * RATE), len(output) - first)):
        t = index / RATE
        last = 0.77 * last + 0.23 * random.uniform(-1.0, 1.0)
        taper = min(1.0, t / 0.015, (duration - t) / 0.04)
        output[first + index] += gain * last * taper * exp(-3.0 * t / duration)


def write_wav(path, samples, maximum):
    peak = max(abs(sample) for sample in samples)
    scale = min(1.0, maximum / peak)
    pcm = array("h", (round(sample * scale * 32767.0) for sample in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(pcm.tobytes())


def grove_loop():
    beat = 0.48
    output = silence(8 * 4 * beat)
    phrases = [
        (50, (62, 69, 74), (74, 76, 78, 81)),
        (47, (59, 66, 74), (83, 81, 78, 76)),
        (43, (55, 62, 71), (74, 79, 78, 76)),
        (45, (57, 64, 73), (73, 76, 81, 78)),
        (50, (62, 69, 74), (74, 78, 81, 83)),
        (47, (59, 66, 74), (81, 86, 83, 81)),
        (43, (55, 62, 71), (79, 78, 76, 74)),
        (45, (57, 64, 73), (76, 73, 76, 69)),
    ]
    for bar, (root, harmony, tune) in enumerate(phrases):
        offset = bar * 4 * beat
        mix_note(output, offset, beat * 0.92, root, 0.065, "wood")
        mix_note(output, offset + 2 * beat, beat * 0.82, root + 7, 0.045, "wood")
        for step, pitch in enumerate(harmony):
            mix_note(output, offset + 0.08 + step * beat, beat * 2.15, pitch, 0.023, "soft")
        for pulse, pitch in zip((0.55, 1.60, 2.56, 3.20), tune):
            mix_note(output, offset + pulse * beat, beat * 0.62, pitch, 0.047)
    return finish_loop(output)


def boss_loop():
    beat = 0.43
    output = silence(8 * 4 * beat)
    phrases = [
        (50, (62, 65, 69, 74)),
        (46, (58, 62, 65, 70)),
        (48, (60, 64, 67, 72)),
        (45, (57, 62, 64, 69)),
        (50, (62, 64, 69, 74)),
        (53, (65, 69, 72, 77)),
        (48, (60, 64, 67, 72)),
        (45, (57, 62, 64, 69)),
    ]
    for bar, (root, theme) in enumerate(phrases):
        offset = bar * 4 * beat
        for step in (0, 1.5, 2, 3.5):
            gain = 0.084 if step == 0 or step == 2 else 0.046
            mix_note(output, offset + step * beat, beat * 0.46, root, gain, "wood")
        for pulse, pitch in zip((0.28, 1.08, 2.25, 3.18), theme):
            mix_note(output, offset + pulse * beat, beat * 0.72, pitch, 0.051, "wood")
        mix_note(output, offset + beat * 1.1, beat * 2.45, theme[1], 0.025, "soft")
        mix_air(output, offset + beat * 3.43, beat * 0.25, 0.046, bar)
    return finish_loop(output)


def finish_loop(samples):
    # A short taper prevents a splice click at the loop boundary.
    margin = round(RATE * 0.018)
    for index in range(margin):
        amount = index / margin
        samples[index] *= amount
        samples[-1 - index] *= amount
    return samples


def cues():
    # Each note is start, duration, pitch, gain, timbre, and optional pitch sweep.
    return {
        "confirm": [(0, .13, 76, .14), (.061, .16, 81, .16)],
        "bolt_fire": [(0, .15, 71, .17, "bell", .24), (.038, .11, 81, .06)],
        "bolt_impact": [(0, .15, 64, .15, "wood", -.29), (.018, .12, 81, .076)],
        "player_hit": [(0, .17, 55, .16, "wood", -.21), (.04, .12, 62, .075, "soft")],
        "enemy_hit": [(0, .095, 66, .14, "wood", -.19)],
        "enemy_death": [(0, .16, 69, .12, "wood", -.14), (.064, .16, 76, .09)],
        "xp_pickup": [(0, .10, 79, .12), (.035, .13, 86, .13)],
        "level_up": [(0, .25, 72, .13), (.076, .22, 76, .14), (.153, .28, 79, .16), (.222, .29, 84, .12)],
        "upgrade_pick": [(0, .15, 76, .13), (.048, .19, 81, .14), (.101, .19, 88, .13)],
        "chain": [(0, .095, 85, .12, "bell", -.42), (.037, .10, 78, .10, "bell", .31), (.073, .11, 83, .079)],
        "flame": [(0, .20, 57, .105, "wood", .40), (.039, .17, 69, .09, "wood")],
        "frost": [(0, .18, 90, .11), (.044, .17, 83, .10), (.088, .20, 78, .08)],
        "guard": [(0, .24, 55, .115, "wood"), (.015, .25, 67, .13), (.042, .24, 79, .10)],
        "boss_intro": [(0, .43, 50, .125, "soft"), (.14, .42, 57, .115, "soft"), (.37, .37, 62, .16, "bell")],
        "boss_stomp": [(0, .33, 40, .24, "wood", -.40), (.02, .18, 52, .095, "wood", -.32)],
        "boss_charge": [(0, .32, 47, .14, "wood", .52), (.025, .16, 76, .065, "wood", -.32)],
        "boss_phase": [(0, .38, 57, .105, "soft"), (.088, .27, 64, .09, "wood"), (.165, .26, 69, .13), (.231, .28, 76, .15)],
        "victory": [(0, .58, 62, .12, "soft"), (.066, .36, 74, .14), (.161, .32, 78, .135), (.258, .29, 81, .15), (.39, .44, 86, .16)],
        "game_over": [(0, .29, 74, .086), (.11, .30, 69, .092), (.26, .37, 66, .091), (.32, .38, 62, .074, "soft")],
        "purchase": [(0, .14, 72, .11), (.049, .14, 77, .12), (.09, .19, 84, .14)],
    }


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Destination assets/audio directory")
    root = parser.parse_args().output
    music = root / "music"
    sfx = root / "sfx"
    music.mkdir(parents=True, exist_ok=True)
    sfx.mkdir(parents=True, exist_ok=True)
    write_wav(music / "grove_walk.wav", grove_loop(), 0.26)
    write_wav(music / "guardian_glade.wav", boss_loop(), 0.26)
    noise = {"chain": .10, "flame": .15, "boss_charge": .30, "boss_stomp": .24, "bolt_fire": .11}
    for index, (name, notes) in enumerate(cues().items()):
        length = max(note[0] + note[1] for note in notes)
        samples = silence(length + 0.028)
        for note in notes:
            mix_note(samples, *note)
        if name in noise:
            mix_air(samples, 0.0, length, noise[name], index)
        write_wav(sfx / (name + ".wav"), samples, 0.26)


if __name__ == "__main__":
    main()
