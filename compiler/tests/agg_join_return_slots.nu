// A struct, an enum, an option or a result that several paths hand to one
// place — the arms of a `?` / `??`, the returns of a function or of a
// closure body — goes through a slot of the frame, not a `phi` of the
// aggregate (AGORA-853). The values are what they were: this file runs
// every shape that takes the slot and prints what it computes, and
// compiler/tests/agg_no_phi_ir.sh holds the IR to it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { i x i y }

: | Shape { Dot Circle i Rect i i }

: | Fault { Low String High i String }

// Several `^` sites: one exit block.
@ classify i n → Shape {
    ? < n 0 { ^ Dot } {}
    ? == % n 2 0 { ^ @ Shape { Circle n } } {}
    ^ @ Shape { Rect n + n 1 }
}

@ area Shape s → i {
    ^ ?? s {
        Dot → 0
        Circle r → * * r r 3
        Rect w h → * w h
    }
}

// An option with an early exit.
@ find_even ( Vec i ) v → ?i {
    : ~ i k 0
    ~ < k ( vec_len [i] v ) {
        : i e ( vec_at [i] v k )
        ? == % e 2 0 { ^ @ ?i { T e } } {}
        = k + k 1
    }
    ^ @ ?i { F 0 }
}

// A result whose error owns a String, on two of five exits.
@ step P p i op → !P Fault {
    ? == op 0 { ^ @ !P Fault { T @ P { + . p x 1 . p y } } } {}
    ? == op 1 { ^ @ !P Fault { T @ P { . p x + . p y 1 } } } {}
    ? == op 2 { ^ @ !P Fault { F @ Fault { Low ( string_from `too low` ) } } } {}
    ? == op 3 { ^ @ !P Fault { F @ Fault { High . p x ( string_from `too high` ) } } } {}
    ^ @ !P Fault { T @ P { 0 0 } }
}

// The try's error exit beside the function's own returns.
@ twice P p i op → !P Fault {
    : P a \ ( step p op )
    : P b \ ( step a op )
    ^ @ !P Fault { T b }
}

// A `?` join of structs, of owned Strings, of options.
@ pick_p b c P a P z → P { ^ ? c a z }

@ pick_s b c → String {
    ^ ? c ( string_from `left` ) ( string_from `right` )
}

@ pick_o b c i n → ?i { ^ ? c @ ?i { T n } @ ?i { F 0 } }

// A `??` join of enums and of structs, a wildcard arm among them.
@ grow Shape s → Shape {
    ^ ?? s {
        Dot → @ Shape { Circle 1 }
        Circle r → @ Shape { Rect r r }
        _ → s
    }
}

@ corner Shape s → P {
    ^ ?? s {
        Dot → @ P { 0 0 }
        Circle r → @ P { r r }
        Rect w h → @ P { w h }
    }
}

// A self-recursive tail call that returns an aggregate stays a loop: two
// million frames deep would not fit the stack.
@ count_down i n P acc → P {
    ? == n 0 { ^ acc } {}
    ^ ( count_down - n 1 @ P { + . acc x 1 + . acc y n } )
}

// A defer registered after the first return and before the last.
@ with_defer i n ( Vec i ) log → P {
    ? < n 0 { ^ @ P { -1 -1 } } {}
    ; { ( vec_push [i] log n ) }
    ? == n 0 { ^ @ P { 0 0 } } {}
    ^ @ P { n * n 2 }
}

// A closure body with two returns, and one whose tail is a join.
@ run_clo i n → i {
    : ( @ P i ) mk \ i k → P {
        ? < k 10 { ^ @ P { k 0 } } {}
        ^ @ P { 10 - k 10 }
    }
    : ( @ ?i i ) half \ i k → ?i { ? == % k 2 0 @ ?i { T / k 2 } @ ?i { F 0 } }
    : P a ( mk n )
    : i h ?? ( half n ) { T q → q F → -1 }
    ^ + + . a x . a y h
}

@ show_fault Fault f → v {
    ?? f {
        Low m → { ( nurl_print `Low ` ) ( nurl_println ( string_data m ) ) }
        High d m → { ( nurl_print `High ` ) ( nurl_print_int d ) ( nurl_print ` ` ) ( nurl_println ( string_data m ) ) }
    }
}

@ main → i {
    // classify + area + grow + corner
    : ~ i n -1
    : ~ i sum 0
    ~ < n 6 {
        : Shape s ( classify n )
        : Shape g ( grow s )
        : P c ( corner g )
        = sum + + + sum ( area s ) ( area g ) + . c x . c y
        = n + n 1
    }
    ( nurl_println_int sum )

    // find_even
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 ) ( vec_push [i] v 5 ) ( vec_push [i] v 8 ) ( vec_push [i] v 9 )
    ( nurl_println_int ?? ( find_even v ) { T e → e F → -1 } )
    : ( Vec i ) odd ( vec_new [i] )
    ( vec_push [i] odd 1 )
    ( nurl_println_int ?? ( find_even odd ) { T e → e F → -1 } )

    // step + twice, every exit
    : ~ i op 0
    ~ < op 5 {
        ?? ( twice @ P { 10 20 } op ) {
            T p → { ( nurl_print_int . p x ) ( nurl_print ` ` ) ( nurl_println_int . p y ) }
            F f → { ( show_fault f ) }
        }
        = op + op 1
    }

    // joins
    : P a ( pick_p T @ P { 1 2 } @ P { 3 4 } )
    : P z ( pick_p F @ P { 1 2 } @ P { 3 4 } )
    ( nurl_println_int + + + . a x . a y * 10 . z x * 10 . z y )
    : String l ( pick_s T )
    : String r ( pick_s F )
    ( nurl_print ( string_data l ) ) ( nurl_print ` ` ) ( nurl_println ( string_data r ) )
    ( nurl_println_int + ?? ( pick_o T 7 ) { T q → q F → 100 } ?? ( pick_o F 7 ) { T q → q F → 100 } )

    // the tail call
    : P deep ( count_down 2000000 @ P { 0 0 } )
    ( nurl_print_int . deep x ) ( nurl_print ` ` ) ( nurl_println_int . deep y )

    // the defer
    : ( Vec i ) log ( vec_new [i] )
    : P d0 ( with_defer -5 log )
    : P d1 ( with_defer 0 log )
    : P d2 ( with_defer 4 log )
    ( nurl_println_int + + + + + . d0 x . d0 y . d1 x . d1 y . d2 x . d2 y )
    ( nurl_println_int ( vec_len [i] log ) )

    // the closures
    ( nurl_println_int + ( run_clo 4 ) ( run_clo 15 ) )
    ^ 0
}
