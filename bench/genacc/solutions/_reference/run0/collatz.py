#!/usr/bin/env python3
# collatz — longest Collatz chain length for starts in [1, 100000).
def steps(n):
    c = 0
    while n > 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        c += 1
    return c


best = 0
for k in range(1, 100000):
    s = steps(k)
    if s > best:
        best = s
print(best)
