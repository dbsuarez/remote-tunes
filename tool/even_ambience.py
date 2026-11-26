"""Makes evened-out copies of ambience sounds: faint ones are turned up and their sharp peaks (crackles)
held down, so they can be as loud as the rest. The originals are not touched.

    python tool/even_ambience.py SOURCE_FOLDER OUTPUT_FOLDER

Needs ffmpeg. Copies are Ogg (it loops without the gap that re-making an MP3 would add). Each file is only
turned up or down by one fixed amount and limited at the top, so the start and end still fit for looping.
"""
import os
import re
import subprocess
import sys

TARGET = -20.0  # the average level aimed for, in dB below full scale (what the app aims for too)
MOST_UP, MOST_DOWN = 30.0, -12.0
TYPES = ('.mp3', '.wav', '.ogg', '.flac')


def levels(path):
    out = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', path, '-af', 'volumedetect', '-f', 'null', os.devnull],
                         capture_output=True, text=True, encoding='utf-8', errors='replace').stderr
    mean = re.search(r'mean_volume:\s*(-?[\d.]+) dB', out)
    peak = re.search(r'max_volume:\s*(-?[\d.]+) dB', out)
    if not mean or not peak:
        raise RuntimeError('could not read the level')
    return float(mean.group(1)), float(peak.group(1))


def make(source, target):
    mean, _ = levels(source)
    gain = max(MOST_DOWN, min(MOST_UP, TARGET - mean))
    # The limiter keeps the peaks under -1 dB without changing the level of the rest.
    chain = f'volume={gain:.2f}dB,alimiter=limit=0.89:attack=5:release=60:level=false'
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', source, '-map', '0:a:0', '-af', chain,
                    '-ar', '44100', '-c:a', 'libvorbis', '-q:a', '5', target], check=True)
    return mean, gain, levels(target)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, out = sys.argv[1], sys.argv[2]
    if os.path.abspath(source) == os.path.abspath(out):
        sys.exit('Give a different folder for the copies.')
    os.makedirs(out, exist_ok=True)
    failed = []
    for name in sorted(os.listdir(source)):
        stem, ext = os.path.splitext(name)
        if ext.lower() not in TYPES:
            continue
        try:
            before, gain, (after, peak) = make(os.path.join(source, name), os.path.join(out, stem.strip() + '.ogg'))
            print(f'{before:6.1f} -> {after:6.1f} dB average (changed {gain:+5.1f}), peak {peak:5.1f}  {stem}')
        except Exception as e:  # one bad file does not stop the rest
            failed.append(name)
            print(f'FAILED {name}: {e}')
    if failed:
        sys.exit(f'{len(failed)} file(s) failed.')


if __name__ == '__main__':
    main()
