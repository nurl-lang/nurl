// param_shadows_fn.nu — a parameter shadows a same-named top-level
// function for the whole body.
//
// The parameter's TYPE went into the inner scope, but the function's
// call metadata — declared parameter roster, FFI roster, arity — lives
// under the same key in an outer scope, and the symbol lookup walks
// outward and found it. So a call that resolved to the parameter was
// checked against a signature it had nothing to do with:
//
//   error: argument 1 to 'handler': value of type 'i64' passed where
//          parameter expects 'i8*'
//   error: call to 'dispatch' has the wrong number of arguments:
//          expected 2, got 1
//
// reported at the CALLEE's line, inside whichever file declared the
// parameter. The cross-file form is the one that bites: a stdlib
// module taking a `dispatch` closure stopped compiling because the
// importing program happened to declare `@ dispatch` with a different
// shape — a name in one file breaking an unrelated function in
// another.

$ `stdlib/core/string.nu`

// Parameter `handler` vs. a global `@ handler` of a different type.
@ run ( @ i i ) handler i x → i { ^ ( handler x ) }

@ handler s tag → i { ^ 42 }

// Parameter `dispatch` vs. a global `@ dispatch` of a different ARITY.
@ route ( @ i i ) dispatch i x → i { ^ ( dispatch x ) }

@ dispatch i a i b → i { ^ + a b }

@ main → i {
    ( nurl_print ( nurl_str_int ( run \ i v → i { ^ + v 1 } 7 ) ) )
    ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( route \ i v → i { ^ * v 10 } 7 ) ) )
    ( nurl_print `\n` )
    // The globals are still callable where nothing shadows them.
    ( nurl_print ( nurl_str_int ( handler `x` ) ) )
    ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( dispatch 20 3 ) ) )
    ( nurl_print `\n` )
    ^ 0
}
