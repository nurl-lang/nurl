// lint_redundant_free.nu — `--lint`: a release call the memory model
// makes redundant.
//
// `( string_free x )`, `( vec_free [T] x )`, … on a local the compiler
// drops anyway, at the tail of a block — nothing but more such calls
// after it, then `^` (every scope ends) or the `}` of the block that
// declared x. The drop there releases exactly what the call did. Every
// `REDUNDANT` line below is reported; every other release call must stay
// silent: an early release (something follows it), a parameter, a
// binding declared outside the block the call ends, a capture released
// inside a closure body, a `*_free_with`, a field, a hand-written
// destructor (a body that frees more than the drop would), and a value
// from a call that hands back something it keeps (a field it replaces):
// the binding does not own that, so the call is the only release.
//
// The shapes an older lint reported as leaks — a handle never freed, a
// temporary handed straight to a call — are not leaks under the memory
// model (they run LSan-clean) and must stay silent too.
//
// Expected: COMPILE OK, warnings for exactly the `REDUNDANT` lines.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String s }

@ fresh → String { ^ ( string_from `fresh` ) }

@ takes String s → i { ^ ( string_len s ) }

@ tail_of_function → i {
    : String s ( string_from `x` )
    : ( Vec i ) v ( vec_new [i] )
    : i n + ( string_len s ) ( vec_len [i] v )
    ( string_free s )  // REDUNDANT
    ( vec_free [i] v )  // REDUNDANT
    ^ n
}

@ before_early_return i k → i {
    : String s ( string_from `x` )
    ? == k 0 { ( string_free s ) ^ 1 } {}  // REDUNDANT
    ^ ( string_len s )
}

@ loop_local → v {
    : ~ i i 0
    ~ < i 2 {
        : String t ( string_from `y` )
        = i + i 1
        ( string_free t )  // REDUNDANT
    }
}

@ early_release i k → i {
    : String s ( string_from `x` )
    : i n ( string_len s )
    ( string_free s )
    ( nurl_print `` )
    ^ + n k
}

@ parameter String p → v {
    ( string_free p )
}

@ outer_binding_in_arm b c → v {
    : String s ( string_from `x` )
    ? c { ( string_free s ) } {}
}

@ in_closure → i {
    : String s ( string_from `x` )
    : ( @ v ) f \ → v { ( string_free s ) }
    ( f )
    ^ 0
}

@ free_with → v {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a` ) )
    ( vec_free_with [String] v \ String x → v {} )
}

@ field → i {
    : Holder h @ Holder { ( string_from `f` ) }
    : i n ( string_len . h s )
    ( string_free . h s )
    ^ n
}

: Msg { ( Vec i ) items }

@ msg_free sink Msg m → v { ( vec_free [i] . m items ) }

@ custom_destructor → v {
    : Msg m @ Msg { ( vec_new [i] ) }
    ( msg_free m )
}

: Conn { ( Vec i ) readable }

unsafe

@ take_readable * Conn c → ( Vec i ) {
    : ( Vec i ) out . c readable
    = . c readable ( vec_new [i] )
    ^ out
}

@ fresh_vec → ( Vec i ) { ^ ( vec_new [i] ) }

@ from_field_handover * Conn c → i {
    : ( Vec i ) r ( take_readable c )
    : i n ( vec_len [i] r )
    ( vec_free [i] r )
    ^ n
}

@ from_fresh_call → i {
    : ( Vec i ) r ( fresh_vec )
    : i n ( vec_len [i] r )
    ( vec_free [i] r )  // REDUNDANT
    ^ n
}

// Formerly "never released" / "owned by nothing": dropped by the
// compiler, nothing to report.
@ never_freed → i {
    : String s ( string_from `never freed` )
    ^ ( string_len s )
}

@ temporary_argument → i {
    ^ + ( takes ( fresh ) ) ( nurl_str_len ( nurl_str_int 7 ) )
}

unsafe

@ main → i {
    ( loop_local ) ( parameter ( string_from `p` ) ) ( outer_binding_in_arm T ) ( free_with ) ( custom_destructor )
    : *Conn c # *Conn ( nurl_zalloc Z Conn )
    = . c readable ( vec_new [i] )
    : i h + ( from_field_handover c ) ( from_fresh_call )
    ( vec_free [i] . c readable ) ( nurl_free # s c )
    ^ - + + + + + + + ( tail_of_function ) ( before_early_return 1 ) ( early_release 0 ) ( in_closure ) ( field ) ( never_freed ) ( temporary_argument ) h 58
}
