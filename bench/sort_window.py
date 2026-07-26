#!/usr/bin/env python3
# benchmark-contract: sort-window;seed=123456789;iterations=2000000;width=8;algorithm=bubble
#
# sort_window — 2M iterations of "derive 8 values from the LCG state,
# bubble-sort them, fold the extremes back into the state". 8 passes of
# up to 7 compare-and-maybe-swap steps each: a compare/branch/store mill
# with a loop-carried dependency through the state.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
MASK = 0xFFFFFFFF

window = [0, 1, 2, 3, 4, 5, 6, 7]
state = 123456789

for i in range(2_000_000):
    state = (state * 1664525 + 1013904223) & MASK

    window[0] = state
    window[1] = state ^ 0xA5A5A5A5
    window[2] = (state + i) & MASK
    window[3] = state * 3
    window[4] = (state - i) & MASK
    window[5] = state >> 3
    window[6] = state << 1
    window[7] = (state + 7) & MASK

    # Textbook bubble sort over 8 slots, kept deliberately naive so
    # every language runs the same instruction mill.
    for p in range(8):
        for j in range(7 - p):
            if window[j] > window[j + 1]:
                window[j], window[j + 1] = window[j + 1], window[j]

    state = state ^ window[0] ^ window[7]

print(state & 0x7FFFFFFFFFFFFFFF)
