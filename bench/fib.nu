// fib — recursive Fibonacci(35). Output: 9227465 (× BENCH_SCALE).
// Naive double recursion, no memoisation: ~29.8M source-level
// evaluations, of which the binary executes ~15M real calls — LLVM
// rewrites the second recursive branch into a loop for every compiled
// peer alike (each fib function keeps exactly one call site). Stresses
// the call/return path and the tokeniser's handling of call syntax.
@ fib i n → i {
    ? < n 2 { ^ n } {}
    ^ + ( fib - n 1 ) ( fib - n 2 )
}

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    // BENCH_SCALE calls of fib(35), summed. The argument is 35 + (total >> 62):
    // always 35 (the total never reaches 2^62), but not provably constant, so
    // no optimiser can hoist the call out of the loop as invariant.
    : ~ i total 0
    : ~ u64 rep 0
    ~ < rep BENCH_SCALE {
        = total + total ( fib + 35 >> total 62 )
        = rep + rep 1
    }
    ( nurl_println_int total )
    ^ 0
}
