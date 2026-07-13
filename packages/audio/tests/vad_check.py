# The bursts in the test signal are at [2,5) and [8,11) seconds. The detector is
# told nothing; this checks what it came back with.
#
# 200 ms of padding either side is deliberate — a segment may start early and end
# late by that much — but it must not MISS any of a burst, and it must not invent
# a third one out of the room noise.
import re
import sys

txt = open(sys.argv[1]).read()
segs = [(float(a), float(b)) for a, b in re.findall(r'^([\d.]+) - ([\d.]+) s$', txt, re.M)]
assert len(segs) == 2, f"expected 2 segments, got {segs}"
for (gs, ge), (ws, we) in zip(segs, [(2.0, 5.0), (8.0, 11.0)]):
    assert ws - 0.30 <= gs <= ws + 0.05, f"start {gs} vs {ws}"
    assert we - 0.05 <= ge <= we + 0.30, f"end {ge} vs {we}"
print("   ", segs)
