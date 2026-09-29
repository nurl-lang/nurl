// lend_back_temps.nu — a temporary argument its callee lends back. The
// callee's result aliases the argument (`^ p`, `^ @ ?T { T p }`) or a part
// of it (`^ . p a`, a `vec_get` element), so the callee's own answer is
// "lent" — but the temporary is the caller's, and nothing else owns it.
// Per call site: handed back whole, the temporary moves into the result;
// handed back in part, the result is copied and the temporary dropped.
// Each shape used to leak the temporary. The sanitizer corpus runs this
// with leak detection.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Pair { String a String b }

% Named [T] { @ nm T self → String }

% Named Pair { @ nm Pair self → String { ^ . self a } }

// Callees defined further down: their summaries are final only at the end.
@ forward_uses → i {
    : ~ i t ( string_len ( fid ( sh ) ) )
    = t + t ( string_len ( ffa ( mk ) ) )
    : String w ( fid ( sh ) )
    ^ + t ( string_len w )
}

@ mk → Pair { ^ @ Pair { ( string_from `first` ) ( string_from `second` ) } }

@ sh → String { ^ ( string_from `hello` ) }

@ fid String s → String { ^ s }

@ ffa Pair p → String { ^ . p a }

@ via String s → String { ^ ( fid s ) }

@ rw String s → ?String {
    ? == 0 ( string_len s ) { ^ @ ?String { F } } {}
    ^ @ ?String { T s }
}

@ pick b c String x String y → String { ? c { ^ x } { ^ y } }

@ tag String s i n → String { ^ s }

@ tag_len String s i n → i { ^ + ( string_len s ) n }

@ gid [T] T x → T { ^ x }

@ wrap_part Pair p → ?String { ^ @ ?String { T . p b } }

@ vfirst ( Vec String ) v → ?String { ^ ( vec_get [String] v 0 ) }

@ mkv → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `elem` ) )
    ^ v
}

// Handed on from a callee that lends a temporary back.
@ ret_whole → String { ^ ( fid ( sh ) ) }

@ ret_part → String { ^ ( ffa ( mk ) ) }

// A part of this frame's own value handed back: the value is dropped on
// the way out, so the part is copied — directly, and through a binding.
@ ret_local_call → String {
    : Pair t ( mk )
    ^ ( ffa t )
}

@ ret_local_binding → String {
    : Pair t ( mk )
    : String w ( ffa t )
    ^ w
}

@ show s label String v → v {
    ( nurl_print label ) ( nurl_print ` ` ) ( nurl_print ( string_data v ) ) ( nurl_print `\n` )
}

@ main → i {
    : String named ( string_from `named` )
    ( show `id` ( fid ( sh ) ) )
    ( show `via` ( via ( sh ) ) )
    ( show `field` ( ffa ( mk ) ) )
    ( show `generic` ( gid [String] ( sh ) ) )
    ( show `pick-temp` ( pick T ( sh ) named ) )
    ( show `pick-named` ( pick F ( sh ) named ) )
    ( show `method` ( nm ( mk ) ) )
    // Named arguments take the same per-argument rule.
    ( show `named-arg` ( tag n : 1 s : ( sh ) ) )
    ( nurl_print_int ( tag_len s : ( sh ) n : 2 ) ) ( nurl_print `\n` )
    ?? ( rw ( sh ) ) { T v → { ( show `option` v ) } F → {} }
    ?? ( wrap_part ( mk ) ) { T v → { ( show `option-part` v ) } F → {} }
    ?? ( vfirst ( mkv ) ) { T v → { ( show `element` v ) } F → {} }
    : String bound ( fid ( sh ) )
    : String bound_part ( ffa ( mk ) )
    ( show `bound` bound )
    ( show `bound-part` bound_part )
    ( show `ret-whole` ( ret_whole ) )
    ( show `ret-part` ( ret_part ) )
    ( show `ret-local-call` ( ret_local_call ) )
    ( show `ret-local-binding` ( ret_local_binding ) )
    ( nurl_print_int ( forward_uses ) ) ( nurl_print `\n` )
    // Discarded.
    ( fid ( sh ) )
    ( ffa ( mk ) )
    ^ 0
}
