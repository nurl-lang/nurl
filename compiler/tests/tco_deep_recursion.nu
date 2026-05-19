// tco_deep_recursion.nu — regression target for tail-call optimisation.
//
// A 5-million-deep tail-recursive countdown that returns a running
// accumulator. Without TCO the recursion would blow the default
// 8 MiB stack at ~200k frames (each frame ~40 B); WITH TCO `gen_call`
// emits `tail call i64 @sum_down(...)` and LLVM's tail-call
// elimination rewrites the recursion into a loop, so the test
// completes in O(1) stack regardless of depth.
//
// The accumulator returns a fixed expected value so the baseline
// can detect both regressions (silent miscompilation) and TCO
// failures (process killed by SIGSEGV → the runner records a
// non-zero EXIT and the diff fires).

@ sum_down i n i acc → i {
    ? <= n 0 { ^ acc } {}
    ^ ( sum_down - n 1 + acc 1 )
}

@ main → v {
    : i n 5000000
    : i s ( sum_down n 0 )
    ( nurl_print ( nurl_str_int s ) ) ( nurl_print `\n` )
}
