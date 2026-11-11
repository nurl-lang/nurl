// generic_binding_at_a_closure_type.nu — `: T w v` inside a generic
// instantiated at a closure type (agora #637, item 4). The instance's body
// spells the type as a slug word (`fn1_3_i64_3_i64`), which is a type only
// where it is noted as one: noted in the scope of the function whose body
// made the instance, it was gone before the instance was compiled, and the
// `:` read the word as the NAME of an inferred binding — "use of undefined
// identifier 'w'". At `[i]` the same generic always compiled.

@ id [T] T v → T { ^ v }

@ hold [T] T v → T {
    : T w v
    ^ w
}

@ hold_call [T] T v → T {
    : T w ( id [T] v )
    ^ w
}

@ twice [T] T v ( @ T T ) f → T {
    : ( @ T T ) g f
    : T once ( g v )
    ^ ( g once )
}

@ main → i {
    : ( @ i i ) inc \ i x → i { ^ + x 1 }
    : ( @ i i ) h ( hold [( @ i i )] inc )
    ( nurl_println_int ( h 41 ) )
    : ( @ i i ) c ( hold_call [( @ i i )] inc )
    ( nurl_println_int ( c 1 ) )
    ( nurl_println_int ( hold [i] 7 ) )
    ( nurl_println_int ( twice [i] 5 inc ) )
    ^ 0
}
