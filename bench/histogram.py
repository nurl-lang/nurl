#!/usr/bin/env python3
# histogram — highest single-digit count in an embedded string.
text = "314159265358979"
hist = [0] * 10
for ch in text:
    o = ord(ch)
    if 48 <= o <= 57:
        hist[o - 48] += 1
print(max(hist))
