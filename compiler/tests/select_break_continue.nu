// select_break_continue.nu — `break`, `continue` and `^` inside the arm
// bodies of a blocking select.
//
// The select lowers to an arm / poll / wait / disarm loop. Its arm bodies
// used to run INSIDE that loop: a `break` left the select's own loop (the
// author's loop kept going) and skipped the disarm, so the waiter was
// freed while the other channels still held it. The bodies now run after
// the loop, with every channel disarmed.

$ `stdlib/std/channel.nu`

@ first_ready ( Channel i ) a ( Channel i ) b → i {
    ~ T {
        ?? {
            [i] a → x { ^ ?? x { T v → v F → -1 } }
            [i] b → y { ^ ?? y { T v → + v 100 F → -2 } }
        }
    }
    ^ 0
}

@ main → i {
    : ( Channel i ) a ( chan_new [i] )
    : ( Channel i ) b ( chan_new [i] )
    ( chan_send [i] a 1 )
    ( chan_send [i] a 2 )
    ( chan_send [i] b 3 )

    // break leaves the author's loop after the first round.
    : ~ i rounds 0
    ~ < rounds 5 {
        = rounds + rounds 1
        ?? {
            [i] a → x { break }
            [i] b → y { break }
        }
    }
    ( nurl_print `rounds after break: ` )
    ( nurl_println_int rounds )

    // continue skips the rest of the author's loop body.
    : ~ i seen 0
    : ~ i k 0
    ~ < k 2 {
        = k + k 1
        ?? {
            [i] a → x { continue }
            [i] b → y { continue }
        }
        = seen + seen 1
    }
    ( nurl_print `bodies reached after continue: ` )
    ( nurl_println_int seen )

    // ^ from an arm: the waiter is disarmed, then dropped on the way out.
    ( chan_send [i] b 4 )
    ( nurl_print `returned: ` )
    ( nurl_println_int ( first_ready a b ) )
    ^ 0
}
