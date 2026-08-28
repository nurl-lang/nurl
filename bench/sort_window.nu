// benchmark-contract: sort-window;seed=123456789;iterations=2000000;width=8;algorithm=bubble
//
// sort_window — 2M iterations of "derive 8 values from the LCG state,
// bubble-sort them, fold the extremes back into the state". 8 passes ×
// up to 7 compare-and-maybe-swap steps per iteration, all on the same
// 64-byte window: a branchless compare/exchange mill (the compilers
// unroll the sort and if-convert every swap to cmov) with a loop-carried
// dependency through the state.
//
// NURL has no fixed-size stack array, so the source allocates the window
// as a `malloc`ed `*u64` block where the C and Rust peers use
// `uint64_t window[8]` / `[u64; 8]` on the stack. This does NOT survive
// to the optimized artifacts: LLVM's -O2 heap-to-stack elides the
// malloc/free pair, inlines the sort, and SROAs the window into
// registers (native) / locals (wasm), so all five implementations run
// the mill out of registers. Measured 2026-08-25: hand-promoting the
// malloc to an alloca in nurlc changed nothing on the wasm artifact and
// made the native binary ~19 % slower (LLVM picks a worse canonical
// form for the pre-promoted IR).
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

// Textbook bubble sort over 8 slots: 8 passes, each shrinking the
// unsorted prefix by one. Kept deliberately naive so every language
// runs the same instruction mill.
@ bubble_sort8 * u64 arr → v {
    : ~ i pass 0
    ~ < pass 8 {
        : ~ i j 0
        ~ < + j 1 - 8 pass {
            : u64 left . arr j
            : u64 right . arr + j 1
            ? > left right {
                = . arr j right
                = . arr + j 1 left
            } {}
            = j + j 1
        }
        = pass + pass 1
    }
}

@ main → i {
    : u64 iterations 2000000
    : u64 mask 0xffffffff
    : *u64 window # *u64 ( malloc * 8 8 )
    : ~ i z 0
    ~ < z 8 {
        = . window z # u64 z
        = z + z 1
    }

    : ~ u64 state 123456789
    : ~ u64 k 0

    ~ < k iterations {
        = state & + * state 1664525 1013904223 mask

        = . window 0 state
        = . window 1 ^^ state 0xa5a5a5a5
        = . window 2 & + state k mask
        = . window 3 * state 3
        = . window 4 & - state k mask
        = . window 5 >> state 3
        = . window 6 << state 1
        = . window 7 & + state 7 mask

        ( bubble_sort8 window )
        = state ^^ ^^ state . window 0 . window 7
        = k + k 1
    }

    ( free window )
    ( nurl_println_int # i & state 0x7fffffffffffffff )
    ^ 0
}
