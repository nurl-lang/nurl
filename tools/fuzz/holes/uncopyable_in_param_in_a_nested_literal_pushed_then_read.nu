// uncopyable_in_param_in_a_nested_literal_pushed_then_read: `( vec_push [KK] v @ KK { @ K { p 0 } 1 } )`, `p` a `% Drop` value with no copy, then the caller reads its argument
// Guard: a literal that is pushed, not handed back, takes the parameter over (it cannot be copied), so the caller's read after the call is refused.
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a nested literal kept by the callee takes an uncopyable parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: K { D d i n }

: KK { K k i m }

@ keep D p → i {
    : ~ ( Vec KK ) v ( vec_new [KK] )
    ( vec_push [KK] v @ KK { @ K { p 0 } 1 } )
    ^ ( vec_len [KK] v )
}

@ main → i {
    : D x @ D { ( string_from `a value long enough to own a heap buffer here` ) }
    ( nurl_println_int ( keep x ) )
    ( nurl_println ( string_data . x s ) )
    ^ 0
}
