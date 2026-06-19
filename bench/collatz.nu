// collatz — longest Collatz chain length for starts in [1, 100000).
// Output: 350. A hot while loop with a branch and integer arithmetic.
@ steps i n → i {
    : ~ i c 0
    : ~ i x n
    ~ > x 1 {
        ? == % x 2 0 { = x / x 2 } { = x + * 3 x 1 }
        = c + c 1
    }
    ^ c
}

@ main → i {
    : ~ i best 0
    : ~ i k 1
    ~ < k 100000 {
        : i s ( steps k )
        ? > s best { = best s } {}
        = k + k 1
    }
    ( nurl_print_int best )
    ^ 0
}
