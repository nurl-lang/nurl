// benchmark-contract: sort-window;seed=123456789;iterations=5000000;width=8;algorithm=bubble
//
// sort_window — 5M iterations of "derive 8 values from the LCG state,
// bubble-sort them, fold the extremes back into the state". 8 passes ×
// up to 7 compare-and-maybe-swap steps per iteration, all on the same
// 64-byte window: a compare/branch/store mill with a loop-carried
// dependency through the state.
//
// NURL has no fixed-size stack array: the window lives in a `malloc`ed
// `*u64` block, where the C and Rust peers use `uint64_t window[8]` /
// `[u64; 8]` on the stack.
//
// Peer protocol (matches sort_window.c / sort_window.rs): the process
// normally prints nothing and reports the checksum through its exit
// status (`checksum & 0x7f`). Passing `--verify` writes the 8
// little-endian checksum bytes to stdout — the C peer spells that
// `-DBENCH_VERIFY`, the Rust peer `--cfg bench_verify`.
& `c` @ putchar i c → i

@ emit_checksum u64 value → v {
    : ~ u64 x value
    : ~ i k 0
    ~ < k 8 {
        ( putchar # i & x 255 )
        = x >> x 8
        = k + k 1
    }
}

@ verify_requested → b {
    : i argc ( nurl_argc )
    : ~ i k 1
    ~ < k argc {
        ? == ( strcmp ( nurl_argv k ) `--verify` ) 0 { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ finish u64 value → i {
    ? ( verify_requested ) { ( emit_checksum value ) } {}
    ^ # i & value 0x7f
}

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
    : u64 iterations 5000000
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
    ^ ( finish state )
}
