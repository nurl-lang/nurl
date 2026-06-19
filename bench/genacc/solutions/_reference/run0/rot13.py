#!/usr/bin/env python3
# rot13 — ROT13 every lowercase letter and print the sum of the byte values.
text = "the quick brown fox jumps over the lazy dog and then the slow purple turtle naps"
total = 0
for c in text:
    o = ord(c)
    if 97 <= o <= 122:
        o = 97 + (o - 97 + 13) % 26
    total += o
print(total)
