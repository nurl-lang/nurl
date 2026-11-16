// drop_parameter_lent_back_whole_through_a_binding_kept_on_one_path_given_a_binding: `: R r ( g0 p )  ^ r`, R with its own `% Drop` (no copy), p kept on another path, the caller handing a binding it still names: the result is the caller's binding's value, which the caller releases
// main 3358873a: accepted (the walk's `@bn`: a whole lend of a value that cannot be copied was left alone); AddressSanitizer: heap-use-after-free. Refused as `^ ( r0 p )` is (AGORA-869).
// map: §7.6 | A2 | rejected | - | agora #765/#743: a % Drop parameter kept on one path and lent back whole through a binding on the other, the caller's argument a binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println `drop R` ) } }

@ g0 R p → R { ^ p }

@ f ( Vec R ) log R p b keep → R { ? keep { ( vec_push [R] log p ) ^ @ R { ( string_from `kept` ) 1 } } {} : R r ( g0 p ) ^ r }

@ run b keep → v {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x @ R { ( string_from `first value long enough for the heap, surely so` ) 1 }
    : R a ( f log x keep )
    ( nurl_println ( string_data . a s ) )
    ( nurl_println_int ( vec_len [R] log ) )
}

@ main → i { ( run T ) ( run F ) ^ 0 }
