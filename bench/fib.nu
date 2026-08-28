// fib — recursive Fibonacci(35). Output: 9227465.
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
    ( nurl_println_int ( fib 35 ) )
    ^ 0
}
