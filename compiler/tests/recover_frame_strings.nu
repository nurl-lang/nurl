// recover_frame_strings.nu — a panic frees the owned string bindings of
// every frame it unwinds, through each function's frame table
// (docs/MEMORY.md §7): the value each binding's slot holds at the panic,
// which is what its scope exit would have freed.
//
// Each case is a binding in a different state when the panic comes:
// bound, re-bound in a loop, released at the end of an inner scope,
// handed to a consuming callee, consumed by a callee that then panics,
// returned to a caller that then panics, deep in a recursion, and moved
// into a struct that escapes to the caller (which must NOT be freed).
// Under the sanitizer run every case is leak-free and free of double
// frees and use-after-free.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Resp { s body i code }

@ bound → v {
    : s a ( nurl_str_cat `bound-` `string` )
    ( nurl_print a ) ( nurl_print `\n` )
    ( panic `bound` )
}

@ rebound_in_loop → v {
    : ~ s acc ( nurl_str_cat `` `` )
    : ~ i k 0
    ~ < k 4 {
        = acc ( nurl_str_cat acc `x` )
        : s step ( nurl_str_cat `step-` ( nurl_str_int k ) )
        ( nurl_print step ) ( nurl_print `\n` )
        = k + k 1
    }
    ( nurl_print acc ) ( nurl_print `\n` )
    ( panic `loop` )
}

@ inner_scope_released i c → v {
    ? > c 0 {
        : s inner ( nurl_str_cat `inner-` `scope` )
        ( nurl_print inner ) ( nurl_print `\n` )
    } {}
    : s outer ( nurl_str_cat `outer-` `binding` )
    ( nurl_print outer ) ( nurl_print `\n` )
    ( panic `scope` )
}

unsafe @ consume sink s x → i {
    : i n ( nurl_str_len x )
    ( nurl_free x )
    ^ n
}

@ handed_to_callee → v {
    : s gone ( nurl_str_cat `handed-` `over` )
    : i n ( consume gone )
    : s kept ( nurl_str_cat `kept-` `after` )
    ( nurl_print ( nurl_str_int n ) ) ( nurl_print kept ) ( nurl_print `\n` )
    ( panic `handed` )
}

unsafe @ consume_then_panic sink s x → i {
    ( nurl_print x ) ( nurl_print `\n` )
    ( panic `in callee` )
    ( nurl_free x )
    ^ 0
}

@ callee_panics_owning → v {
    : s mine ( nurl_str_cat `callee-` `owns-it` )
    : i n ( consume_then_panic mine )
    ( nurl_print ( nurl_str_int n ) )
}

@ make_string i k → s {
    : s made ( nurl_str_cat `made-` ( nurl_str_int k ) )
    ^ made
}

@ returned_then_panic → v {
    : s got ( make_string 7 )
    ( nurl_print got ) ( nurl_print `\n` )
    ( panic `returned` )
}

@ deep i d → i {
    : s level ( nurl_str_cat `level-` ( nurl_str_int d ) )
    ? == d 0 { ( panic `deep` ) } {}
    : i r ( deep - d 1 )
    ^ + r ( nurl_str_len level )
}

@ guard ( @ v ) cl → v {
    : !v PanicInfo r ( recover cl )
    ?? r {
        T _ → ( nurl_print `ok\n` )
        F p → { ( nurl_print `caught ` ) ( nurl_print ( string_data . p msg ) ) ( nurl_print `\n` )
            ( panic_info_free p ) }
    }
}

unsafe @ main → i {
    ( guard \ → v { ( bound ) } )
    ( guard \ → v { ( rebound_in_loop ) } )
    ( guard \ → v { ( inner_scope_released 1 ) } )
    ( guard \ → v { ( handed_to_callee ) } )
    ( guard \ → v { ( callee_panics_owning ) } )
    ( guard \ → v { ( returned_then_panic ) } )
    ( guard \ → v { : i r ( deep 40 ) ( nurl_print ( nurl_str_int r ) ) } )

    // A struct built from a fresh string escapes into a by-ref-captured
    // caller binding, then the closure panics: the caller owns the field
    // now, and it must survive the unwind.
    : ~ Resp out @ Resp { `none` 500 }
    : !v PanicInfo re ( recover \ → v {
        : Resp tmp @ Resp { ( nurl_str_cat `escaped-` `field` ) 201 }
        = out tmp
        : s after ( nurl_str_cat `after-` `escape` )
        ( nurl_print after ) ( nurl_print `\n` )
        ( panic `esc` )
    } )
    ?? re { T _ → {} F p → ( panic_info_free p ) }
    ( nurl_print `out.body=` ) ( nurl_print . out body ) ( nurl_print `\n` )
    ( nurl_free # s . out body )
    ( nurl_print `alive\n` )
    ^ 0
}
