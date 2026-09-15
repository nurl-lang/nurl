#!/usr/bin/env python3
"""Walk an MP3 file frame by frame and check that it tiles the file exactly.

No decoder is involved. Every frame header says how long its frame is, so a
correct file is a chain: the next sync word must land exactly where the
previous frame's length says it will. A single bit written short or long
anywhere in the bitstream breaks the chain, which is the failure mode an
encoder has and a listener cannot hear until it is bad.

usage: mp3_frames.py <file.mp3> <expected_rate> <expected_channels> <expected_kbps>
"""
import sys

V_25, V_RES, V_2, V_1 = 0, 1, 2, 3
RATES = {V_1: (44100, 48000, 32000), V_2: (22050, 24000, 16000), V_25: (11025, 12000, 8000)}
BITRATES = [
    (-1, -1, -1, -1), (8, -1, 8, 32), (16, -1, 16, 40), (24, -1, 24, 48),
    (32, -1, 32, 56), (40, -1, 40, 64), (48, -1, 48, 80), (56, -1, 56, 96),
    (64, -1, 64, 112), (-1, -1, 80, 128), (-1, -1, 96, 160), (-1, -1, 112, 192),
    (-1, -1, 128, 224), (-1, -1, 144, 256), (-1, -1, 160, 320), (-1, -1, -1, -1),
]


def main():
    path, want_rate, want_ch, want_kbps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    data = open(path, 'rb').read()
    pos, frames, samples = 0, 0, 0
    while pos + 4 <= len(data):
        h = int.from_bytes(data[pos:pos + 4], 'big')
        if (h >> 21) & 0x7ff != 0x7ff:
            raise SystemExit(f'frame {frames}: no sync word at byte {pos}')
        version = (h >> 19) & 3
        layer = (h >> 17) & 3
        bri = (h >> 12) & 15
        sri = (h >> 10) & 3
        pad = (h >> 9) & 1
        mode = (h >> 6) & 3
        if version == V_RES:
            raise SystemExit(f'frame {frames}: reserved MPEG version')
        if layer != 1:
            raise SystemExit(f'frame {frames}: layer field {layer} is not Layer III')
        if sri == 3:
            raise SystemExit(f'frame {frames}: reserved sample rate')
        rate = RATES[version][sri]
        kbps = BITRATES[bri][version]
        if kbps <= 0:
            raise SystemExit(f'frame {frames}: bitrate index {bri} is free or forbidden')
        ch = 1 if mode == 3 else 2
        if rate != want_rate or ch != want_ch or kbps != want_kbps:
            raise SystemExit(f'frame {frames}: {rate} Hz {ch} ch {kbps} kbps, wanted '
                             f'{want_rate} Hz {want_ch} ch {want_kbps} kbps')
        per = 1152 if version == V_1 else 576
        length = (per // 8) * kbps * 1000 // rate + pad
        if pos + length > len(data):
            raise SystemExit(f'frame {frames}: runs {pos + length - len(data)} bytes past the end')
        pos += length
        frames += 1
        samples += per
    if pos != len(data):
        raise SystemExit(f'{len(data) - pos} trailing bytes belong to no frame')
    if frames == 0:
        raise SystemExit('no frames at all')
    print(f'ok {frames} frames, {samples} samples, {samples / want_rate:.3f} s, tiles the file exactly')


main()
