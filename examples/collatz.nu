// collatz.nu — Collatz conjecture (3n + 1)
//
// Demonstrates:
//   - While loops (~ cond { body })
//   - Conditionals (? cond then else)
//   - Prefix arithmetic (+, *, /, %)
//   - Mutable state updates

@ collatz i start → v {
    : ~ i current start
    : ~ i steps 0

    ( nurl_print `Collatz sequence for ` )
    ( nurl_print ( nurl_str_int current ) )
    ( nurl_print `:\n` )

    ~ > current 1 {
        ( nurl_print ( nurl_str_int current ) )
        ( nurl_print ` -> ` )

        : b is_even == 0 % current 2

        ? is_even {
            = current / current 2
        } {
            = current + * 3 current 1
        }

        = steps + steps 1
    }

    ( nurl_print `1\nTotal steps: ` )
    ( nurl_print ( nurl_str_int steps ) )
    ( nurl_print `\n` )
}

@ main → i {
    // 27 is a classic starting number that takes 111 steps!
    ( collatz 27 )
    ^ 0
}
