// diag_type_predicate_arm_in_safe_code.nu — in safe code both arms of a
// `?` are compiled and checked, whatever the condition: a type predicate
// that is false for an instance does not excuse the arm it leaves out
// (docs/spec.md §8.5; Agora #659). `describe [i]` hands an `i` to a
// function that takes a Bomb, and is refused. The `unsafe` form of the
// same function compiles: type_predicate_static_arm.nu.

$ `stdlib/core/string.nu`

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ tag_len Bomb b → i { ^ ( string_len . b tag ) }

@ describe [T] T x → i {
    ? ( mem_drop_runs_code [T] ) { ^ ( tag_len x ) } {}
    ^ -1
}

@ main → i {
    ( nurl_println ( nurl_str_int ( describe [i] 7 ) ) )
    ^ 0
}
