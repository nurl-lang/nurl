// closure_type_nested.nu — a closure type whose RETURN is a closure.
//
// The middleware shape: takes a handler, returns a handler. Both
// helpers that read a function type's parameter list took the FIRST
// `(` in the LLVM string, which is the parameter list's — until the
// return type is itself a function type and brings its own:
//
//   ( @ ( @ i i ) ( @ i i ) )  →  { {i64(i8*,i64)*,i8*} (i8*, …)*, i8* }
//                                    ^ first `(` belongs to the RETURN
//
// so the arity check and the argument-type check were both read off
// the return value. `( mw h )` was rejected as passing a closure where
// an `i` was declared — a correct program, with an error message
// describing a type nobody wrote. Found writing `http_app_use`, which
// is exactly this shape.

$ `stdlib/core/string.nu`

@ apply ( @ ( @ i i ) ( @ i i ) ) mw ( @ i i ) h i x → i {
    : ( @ i i ) g ( mw h )
    ^ ( g x )
}

@ main → i {
    : ( @ i i ) inc \ i v → i { ^ + v 1 }
    : ( @ ( @ i i ) ( @ i i ) ) twice \ ( @ i i ) f → ( @ i i ) {
        ^ \ i v → i { ^ ( f ( f v ) ) }
    }
    // 5 → inc → inc → 7
    ( nurl_print ( nurl_str_int ( apply twice inc 5 ) ) ) ( nurl_print `\n` )
    // …and the plain shape still works beside it.
    ( nurl_print ( nurl_str_int ( inc 41 ) ) ) ( nurl_print `\n` )
    ^ 0
}
