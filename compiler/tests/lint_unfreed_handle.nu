// lint_unfreed_handle.nu — `--lint`: a Vec or String nobody releases.
//
// `Vec` and `String` are the two handles the compiler deliberately does
// NOT auto-drop (docs/MEMORY.md §7.4), so forgetting one leaks with no
// diagnostic anywhere. This reports a binding that owns one and never
// lets go of it.
//
// Ownership leaves a binding by exactly the routes the compiler already
// models, and each has a case below that must stay SILENT: a `*_free`
// destructor, a `sink` argument, an alias copy into an immutable
// binding, a `^`-return, a store into an aggregate literal, a store
// into a struct field, and an argument the callee embeds. A binding
// that merely BORROWS — a mutable cursor alias, or a view a callee
// built over a parameter — never owned anything and must stay silent
// too.
//
// Expected: COMPILE OK, with warnings for exactly `leaked` and `vleak`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String s }

// A handle stored into an aggregate — the struct owns it now.
@ hold String s → Holder { ^ @ Holder { s } }

@ leaked → i {
    : String s ( string_from `never freed` )
    ^ ( string_len s )
}

@ vleak → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ ( vec_len [i] v )
}

@ freed → i {
    : String s ( string_from `ok` )
    : i n ( string_len s )
    ( string_free s )
    ^ n
}

@ returned → String { ^ ( string_from `ok` ) }

@ aliased → String {
    : String s ( string_from `ok` )
    : String t s
    ^ t
}

@ into_aggregate → Holder {
    : String s ( string_from `ok` )
    ^ @ Holder { s }
}

@ into_callee → Holder {
    : String s ( string_from `ok` )
    ^ ( hold s )
}

@ cursor ( Vec i ) src → i {
    : ~ ( Vec i ) cur src
    ^ ( vec_len [i] cur )
}

@ main → i {
    ^ + + + + + ( leaked ) ( vleak ) ( freed )
    ( string_len ( returned ) )
    ( string_len ( aliased ) )
    0
}
