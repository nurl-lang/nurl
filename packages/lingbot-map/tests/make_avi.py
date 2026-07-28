#!/usr/bin/env python3
# Assemble an MJPEG AVI from image files, with no ffmpeg and no cv2 —
# just Pillow for the JPEG encode and struct for the RIFF tree. This is
# the suite's video fixture generator, and doubles as documentation of
# the exact container layout src/video.nu parses: RIFF('AVI ') ->
# LIST(hdrl){ avih, LIST(strl){ strh(vids/MJPG, dwScale/dwRate), strf } }
# -> LIST(movi){ 00dc = one complete JPEG per frame }.
#
#   make_avi.py <out.avi> <fps> <frame.png> ...
import io
import struct
import sys

from PIL import Image

out_path, fps = sys.argv[1], int(sys.argv[2])
frames = []
w = h = 0
for p in sys.argv[3:]:
    im = Image.open(p).convert("RGB")
    w, h = im.size
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=92)
    frames.append(buf.getvalue())
assert frames, "no frames given"


def chunk(fourcc, data):
    pad = b"\0" if len(data) % 2 else b""
    return fourcc + struct.pack("<I", len(data)) + data + pad


def lst(t, payload):
    return chunk(b"LIST", t + payload)


biggest = max(len(f) for f in frames)
strh = struct.pack("<4s4sIHHIIIIIIiI4H", b"vids", b"MJPG", 0, 0, 0, 0,
                   1, fps, 0, len(frames), biggest, -1, 0, 0, 0, w, h)
strf = struct.pack("<IiiHH4sIiiII", 40, w, h, 1, 24, b"MJPG", w * h * 3,
                   0, 0, 0, 0)
avih = struct.pack("<IIIIIIIIIIIIII", 1000000 // fps, 0, 0, 0x10,
                   len(frames), 0, 1, biggest, w, h, 0, 0, 0, 0)
hdrl = lst(b"hdrl", chunk(b"avih", avih)
           + lst(b"strl", chunk(b"strh", strh) + chunk(b"strf", strf)))
movi = lst(b"movi", b"".join(chunk(b"00dc", f) for f in frames))
payload = b"AVI " + hdrl + movi
with open(out_path, "wb") as f:
    f.write(b"RIFF" + struct.pack("<I", len(payload)) + payload)
print("%s: %d frames %dx%d @ %d fps" % (out_path, len(frames), w, h, fps))
