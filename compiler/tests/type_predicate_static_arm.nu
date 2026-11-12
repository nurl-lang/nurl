// type_predicate_static_arm.nu — a statement `?` on a type predicate
// compiles only the arm the constant selects, in code that vouches for
// itself (docs/spec.md §8.5; Agora #659).
//
// `( mem_drop_runs_code [T] )` is a constant of the instance: T for a
// `% Drop` type, a closure or a handle, F for plain data and for a String.
// `describe` is `unsafe`, as the library code that asks such a question
// is: its first arm hands `x` to a function that takes a Bomb, which for
// T = i or T = String would not compile — and is not compiled. (The same
// function written as safe code is refused for those instances:
// diag_type_predicate_arm_in_safe_code.nu.) Before, the arm the constant
// left out was generated all the same, and everything it named was
// instantiated: every `( HashMap i String )` paid for the release a map of
// destructor values needs.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ tag_len Bomb b → i { ^ ( string_len . b tag ) }

unsafe @ describe [T] T x → i {
    ? ( mem_drop_runs_code [T] ) { ^ ( tag_len x ) } {}
    ^ -1
}

// Both arms are blocks, and the one that goes is the second.
unsafe @ either [T] T x → i {
    ? ( mem_drop_runs_code [T] ) { ^ 1 } { ^ + x 0 }
}

// Several types: true when one of them runs code.
unsafe @ any_of [A B] → i {
    ? ( mem_drop_runs_code [A B] ) { ^ 1 } {}
    ^ 0
}

@ main → i {
    : Bomb b @ Bomb { ( string_from `tick` ) }
    ( nurl_println ( nurl_str_cat `i: ` ( nurl_str_int ( describe [i] 7 ) ) ) )
    ( nurl_println ( nurl_str_cat `String: ` ( nurl_str_int ( describe [String] ( string_from `plain text` ) ) ) ) )
    ( nurl_println ( nurl_str_cat `Bomb: ` ( nurl_str_int ( describe [Bomb] b ) ) ) )
    ( nurl_println ( nurl_str_cat `either i: ` ( nurl_str_int ( either [i] 41 ) ) ) )
    ( nurl_println ( nurl_str_cat `i, String: ` ( nurl_str_int ( any_of [i String] ) ) ) )
    ( nurl_println ( nurl_str_cat `i, Bomb: ` ( nurl_str_int ( any_of [i Bomb] ) ) ) )
    ( nurl_println ( nurl_str_cat `Vec of Bomb: ` ( nurl_str_int ( any_of [( Vec Bomb ) i] ) ) ) )
    ( nurl_println ( nurl_str_cat `Rc of i: ` ( nurl_str_int ( any_of [( Rc i ) i] ) ) ) )
    ( nurl_println ( nurl_str_cat `closure: ` ( nurl_str_int ( any_of [( @ i ) i] ) ) ) )
    ^ 0
}
