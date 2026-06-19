#!/usr/bin/env python3
# csv_sum — sum every integer in an embedded ','/';'-separated grid.
text = "12,3,45;6,78,9;100,2,33"
total = 0
cur = 0
for ch in text:
    o = ord(ch)
    if 48 <= o <= 57:
        cur = cur * 10 + (o - 48)
    else:
        total += cur
        cur = 0
total += cur
print(total)
