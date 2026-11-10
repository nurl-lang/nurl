// temporary_read_through_with_a_dot_never_released: agora #545 — a value nothing names (a call's result, a field taken out of one) read through with `.`: `. ( mk ) length`, `. . ( mkp ) xs length`, a `~` loop over a field of a call's result. The read took what it wanted and the temporary was released by nobody.
// Closed: a read through a temporary releases it where the read is done with it, or gives it an owner for the rest of the scope where what it read is still inside (a loop over its field).
// main (before this PR): LeakSanitizer, each temporary.
// map: §7.6 | A2 | runs-clean | - | agora #545: a temporary read through with `.` (a length, a field, a loop over a field) was never released (leak)
$ `stdlib/core/string.nu`

: P { String name [i xs }

@ mk → [i { ^ [i | 1 2 3] }
@ mkp → P { ^ @ P { ( string_from `a long enough string to be on the heap, one` ) [i | 4 5] } }

@ main → i {
    ( nurl_println ( nurl_str_int . ( mk ) length ) )
    ( nurl_println ( nurl_str_int . . ( mkp ) xs length ) )
    ( nurl_println ( nurl_str_int ( string_len . ( mkp ) name ) ) )
    ~ x . ( mkp ) xs { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
