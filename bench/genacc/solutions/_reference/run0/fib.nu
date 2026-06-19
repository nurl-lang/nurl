// fib — recursive Fibonacci(35). Output: 9227465.
// Naive double recursion: ~29M calls, no memoisation. Stresses the
// function-call path and the tokeniser's handling of call syntax.
@ fib i n → i {
    ? < n 2 { ^ n } {}
    ^ + ( fib - n 1 ) ( fib - n 2 )
}

@ main → i {
    ( nurl_print_int ( fib 35 ) )
    ^ 0
}
