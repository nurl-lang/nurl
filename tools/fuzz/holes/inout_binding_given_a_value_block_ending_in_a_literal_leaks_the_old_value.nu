// inout_binding_given_a_value_block_ending_in_a_literal_leaks_the_old_value: agora #545 — `= p [i | 3 4]` over an `inout [i`, and `= p { … @ P { … } }` / `= p { … [i | z 4] }` over an `inout` struct, option or slice: the new value was stored over the caller's old one, which nobody released.
// Closed: a slice literal, and a value block that ends in a struct or a slice literal, is a new value an `inout` target takes over — the value it held is released (gen_assign_store, __io_lit).
// main (before this PR): LeakSanitizer, the caller's old value on every call (16 bytes for the slice, the String for the struct and the option).
// map: §7.6 | A2 | runs-clean | - | agora #545: an `inout` owner assigned a slice literal or a value block ending in a literal leaked the value it held
$ `stdlib/core/string.nu`

: P { String name i n }

@ setl inout [i p → v { = p [i | 3 4] }

@ setb inout [i p → v { = p { : i z 3 [i | z 4] } }

@ setn inout [i p → v { = p { { [i | 5 6 7] } } }

@ sets inout P p → v { = p { : i z 1 @ P { ( string_from `a new heap string that is long enough to be on the heap` ) z } } }

@ seto inout ?String p → v { = p { : i z 1 @ ?String { T ( string_from `a new heap string that is long enough to be on the heap` ) } } }

@ setq inout ?[i p → v { = p { : i z 1 @ ?[i { T [i | z 2 3] } } }

@ show [i p → v { ~ x p { ( nurl_println ( nurl_str_int x ) ) } }

@ main → i {
    : ~ [i e [i | 1 2]
    ( setl e ) ( show e )
    ( setb e ) ( show e )
    ( setn e ) ( show e )
    : ~ P r @ P { ( string_from `the old heap string that is long enough to be on the heap` ) 1 }
    ( sets r )
    ( nurl_println ( string_data . r name ) )
    : ~ ?String o @ ?String { T ( string_from `the old heap string that is long enough to be on the heap` ) }
    ( seto o )
    ?? o { T q → { ( nurl_println ( string_data q ) ) } F → {} }
    : ~ ?[i os @ ?[i { T [i | 4 4] }
    ( setq os )
    ?? os { T q → { ( show q ) } F → {} }
    ^ 0
}
