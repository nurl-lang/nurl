// defer_in_a_loop_body.nu — a `;` defer inside a loop body (agora #655).
// A defer runs once, at the function's exit, if its `;` was reached in any
// round, and a binding it reads lives until it runs — every round's. What
// stands above the `;` in the loop body runs, from the second round on,
// with the defer armed:
//   brk      a `break` above the `;` leaves the round's binding to the
//            defer, which reads it — and so do a `^` and a `\` there
//            (`ret`, `try`), and a binding made before the loop (`outer`);
//   rounds   each round's binding of a name the defer reads is released
//            once, after the defer chain, newest first: a String, a Vec, a
//            struct with a destructor of its own, a closure's environment;
//   order    …in the reverse of the order they were bound in;
//   wrapped  …and so is an option's or a result's payload (agora #671):
//            a `?String`, a `!String String`, a `?R` whose `R` has a
//            destructor, which runs once per round;
//   moved    …unless that round handed it on;
//   views    a view of an earlier round's binding (a closure over it, a
//            `string_data`, a payload) that the defer still reads is good:
//            that binding is not released when the next round binds the
//            name again;
//   cont     a `continue` above the `;`, and a for-each loop;
//   nested   the `;` in an inner loop, exits of both loops above it;
//   arm      the binding and its `;` inside an arm of the loop body;
//   handed   a `^` above the `;` that hands back what the defer reads.
// Before, a `break`, a `^` or a `\` above the `;` freed what the defer
// read, and every round's value but the last was never released.
// (A `^` or a `\` above the `;` does not run the defer an earlier round
// armed: `ret`, `try`, `outer`, `cont`, `nested`, `arm` and `handed` print
// no defer line on that way out. That is agora #670; those lines of the
// golden change when it is closed.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String name i id }

% Drop R { @ drop R r → v { ( nurl_print `drop ` ) ( nurl_println_int . r id ) } }

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

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

@ order i n → i {
    : ~ i k 0
    ~ < k n {
        : R a @ R { ( string_from `order: a name long enough for a heap buffer` ) + 10 k }
        : R b @ R { ( string_from `order: a name long enough for a heap buffer` ) + 20 k }
        ; { ( nurl_print `order: the defer sees ` ) ( nurl_println_int + . a id . b id ) }
        = k + k 1
    }
    ^ k
}

: | Msg { Text String Quiet }

@ views i n → i {
    : ~ i k 0
    ~ < k n {
        : String g ( mk `views: a loop string long enough for a heap buffer ` k )
        : Msg m ? == k 0 @ Msg { Text ( mk `views: a payload long enough for a heap buffer ` k ) } @ Msg { Quiet }
        ? == k 0 {
            : ( @ i i ) add \ i y → i { ^ + y ( string_len g ) }
            : s d ( string_data g )
            ; { ( nurl_println_int ( add 1 ) ) ( nurl_println d ) }
        } {}
        ?? m { Text t → { ; { ( nurl_println ( string_data t ) ) } } Quiet → {} }
        = k + k 1
    }
    ^ k
}

@ wrapped i n → i {
    : ~ i k 0
    ~ < k n {
        : ?String o @ ?String { T ( mk `wrapped: an option's string, long enough for the heap ` k ) }
        : !String String r ? == % k 2 0 @ !String String { T ( mk `wrapped: a result's value, long enough for the heap ` k ) } @ !String String { F ( mk `wrapped: a result's error, long enough for the heap ` k ) }
        : ?R q @ ?R { T @ R { ( string_from `wrapped: a name long enough for a heap buffer` ) + 30 k } }
        ? == k 2 { break } {}
        ; {
            ?? o { T t → ( nurl_println ( string_data t ) ) F → ( nurl_println `wrapped: none` ) }
            ?? r { T t → ( nurl_println ( string_data t ) ) F e → ( nurl_println ( string_data e ) ) }
            ?? q { T x → ( nurl_println_int . x id ) F → ( nurl_println `wrapped: no R` ) }
        }
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
    ( nurl_println_int ( brk 1 ) )
    ( nurl_println_int ( brk 0 ) )
    ( nurl_println_int ( ret 2 ) )
    : !i String t ( try )
    ?? t { T v → ( nurl_println_int v ) F e → ( nurl_println ( string_data e ) ) }
    ( nurl_println_int ( outer 1 ) )
    ( nurl_println_int ( outer 9 ) )
    ( nurl_println_int ( rounds 4 ) )
    ( nurl_println_int ( rounds 2 ) )
    ( nurl_println_int ( order 2 ) )
    ( nurl_println_int ( views 3 ) )
    ( nurl_println_int ( wrapped 4 ) )
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
