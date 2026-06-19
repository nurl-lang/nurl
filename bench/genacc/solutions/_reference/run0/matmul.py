#!/usr/bin/env python3
# matmul — multiply two 128x128 integer matrices, print the trace.
N = 128
a = [0] * (N * N)
b = [0] * (N * N)
c = [0] * (N * N)

for i in range(N):
    for j in range(N):
        idx = i * N + j
        a[idx] = idx % 7
        b[idx] = (i + j) % 5

for ri in range(N):
    for cj in range(N):
        s = 0
        for k in range(N):
            s += a[ri * N + k] * b[k * N + cj]
        c[ri * N + cj] = s

tr = 0
for d in range(N):
    tr += c[d * N + d]
print(tr)
