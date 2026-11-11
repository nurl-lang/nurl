// defer_in_a_loop_body.nu — a `;` defer inside a loop body (agora #655).
// A defer runs once, at the function's exit, if its `;` was reached in any
// round. What stands above the `;` in the loop body runs, from the second
// round on, with the defer armed:
//   above    a `^` above the `;` runs the defer an earlier round armed;
//   brk      a `break` above the `;` leaves the round's binding to the
//            defer, which reads it — and the `^` twin, and a `\` try;
//   outer    …and so does a binding made before the loop;
//   rounds   the slot holds the last value bound: each round's binding
//            releases the one before it (a String, a Vec, a struct with a
//            destructor of its own, a closure's environment);
//   moved    …unless that round handed it on;
//   cont     a `continue` above the `;`, and a for-each loop;
//   nested   the `;` in an inner loop, exits of both loops above it;
//   arm      the binding and its `;` inside an arm of the loop body;
//   handed   a `^` above the `;` that hands back what the defer reads.
// Before, the first skipped the defer, the next two freed what it read,
// and every round's value but the last leaked.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String name i id }

% Drop R { @ drop R r → v { ( nurl_print `drop ` ) ( nurl_println_int . r id ) } }

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ above i n → i {
    : ~ i k 0
    ~ < k 3 {
        ? == k n { ^ + 100 k } {}
        ; { ( nurl_println `above: the loop's defer ran` ) }
        = k + k 1
    }
    ^ k
}

@ brk i n → i {
    : ~ i k 0
    ~ < k 3 {
        : String g ( mk `brk: a loop string long enough for a heap buffer ` k )
        ? == k n { break } {}
        ; { ( nurl_println ( string_data g ) ) }
        = k + k 1
    }
    ^ k
}

@ ret i n → i {
    : ~ i k 0
    ~ T {
        : ~ ( Vec String ) v ( vec_new [String] )
        ( vec_push [String] v ( mk `ret: an element long enough for a heap buffer ` k ) )
        ? == k n { ^ + 100 k } {}
        ; { ( nurl_println ( string_data ( vec_at [String] v 0 ) ) ) }
        = k + k 1
    }
    ^ k
}

@ may i k → !i String { ? == k 1 { ^ @ !i String { F ( string_from `try: an error long enough for a heap buffer` ) } } {} ^ @ !i String { T k } }

@ try → !i String {
    : ~ i k 0
    ~ < k 3 {
        : String g ( mk `try: a loop string long enough for a heap buffer ` k )
        : !i String r ( may k )
        : i v \ r
        ; { ( nurl_println ( string_data g ) ) }
        = k + + k 1 * v 0
    }
    ^ @ !i String { T k }
}

@ outer i n → i {
    : String x ( string_from `outer: a string bound before the loop, long enough` )
    : ~ i k 0
    ~ < k 3 {
        ? == k n { ^ + 100 k } {}
        ; { ( nurl_println ( string_data x ) ) }
        = k + k 1
    }
    ^ k
}

@ rounds i n → i {
    : ~ i k 0
    ~ < k n {
        : R r @ R { ( string_from `rounds: a name long enough for a heap buffer` ) k }
        : String g ( mk `rounds: a loop string long enough for a heap buffer ` k )
        : ( @ i i ) add \ i x → i { ^ + x ( string_len g ) }
        ? == k 2 { ^ 22 } {}
        ; { ( nurl_print `rounds: the defer sees ` ) ( nurl_println_int . r id ) ( nurl_println_int ( add 1 ) ) }
        = k + k 1
    }
    ^ k
}

@ moved i n → i {
    : ~ ( Vec String ) keep ( vec_new [String] )
    : ~ i k 0
    ~ < k n {
        : String g ( mk `moved: a loop string long enough for a heap buffer ` k )
        ; { ( nurl_println_int ( vec_len [String] keep ) ) }
        ? == % k 2 0 { ( vec_push [String] keep g ) } {}
        = k + k 1
    }
    ^ ( vec_len [String] keep )
}

@ cont ( Vec i ) v → i {
    ~ e v {
        : String g ( mk `cont: a loop string long enough for a heap buffer ` e )
        ? == e 2 { continue } {}
        ? == e 4 { ^ 44 } {}
        ; { ( nurl_println ( string_data g ) ) }
    }
    ^ 0
}

@ nested i n → i {
    : ~ i a 0
    ~ < a 3 {
        : String o ( mk `nested: an outer-loop string long enough for a heap ` a )
        ? == a n { ^ + 100 a } {}
        : ~ i b 0
        ~ < b 2 {
            : String g ( mk `nested: an inner-loop string long enough for a heap ` b )
            ? & == a 1 == b 1 { break } {}
            ; { ( nurl_println ( string_data o ) ) ( nurl_println ( string_data g ) ) }
            = b + b 1
        }
        = a + a 1
    }
    ^ a
}

@ arm i n → i {
    : ~ i k 0
    ~ < k 4 {
        ? == k n { ^ + 100 k } {}
        ? == % k 2 0 {
            : String g ( mk `arm: an arm string long enough for a heap buffer ` k )
            ; { ( nurl_println ( string_data g ) ) }
        } {}
        = k + k 1
    }
    ^ k
}

@ handed i n → String {
    : ~ i k 0
    ~ < k 3 {
        : String g ( mk `handed: a loop string long enough for a heap buffer ` k )
        ? == k n { ^ g } {}
        ; { ( nurl_println_int ( string_len g ) ) }
        = k + k 1
    }
    ^ ( string_from `handed: fell off` )
}

@ main → i {
    ( nurl_println_int ( above 1 ) )
    ( nurl_println_int ( above 0 ) )
    ( nurl_println_int ( above 9 ) )
    ( nurl_println_int ( brk 1 ) )
    ( nurl_println_int ( brk 0 ) )
    ( nurl_println_int ( ret 2 ) )
    : !i String t ( try )
    ?? t { T v → ( nurl_println_int v ) F e → ( nurl_println ( string_data e ) ) }
    ( nurl_println_int ( outer 1 ) )
    ( nurl_println_int ( outer 9 ) )
    ( nurl_println_int ( rounds 4 ) )
    ( nurl_println_int ( rounds 2 ) )
    ( nurl_println_int ( moved 5 ) )
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 ) ( vec_push [i] v 2 ) ( vec_push [i] v 3 ) ( vec_push [i] v 4 ) ( vec_push [i] v 5 )
    ( nurl_println_int ( cont v ) )
    ( nurl_println_int ( nested 2 ) )
    ( nurl_println_int ( nested 9 ) )
    ( nurl_println_int ( arm 3 ) )
    : String h1 ( handed 1 ) ( nurl_println ( string_data h1 ) )
    : String h2 ( handed 9 ) ( nurl_println ( string_data h2 ) )
    ^ 0
}
