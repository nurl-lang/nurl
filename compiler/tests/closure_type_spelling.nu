// closure_type_spelling.nu — one closure type, one spelling.
//
// nurlc compares types as strings. parse_type spelled an ANNOTATED
// closure type `{ R (i8*, P…)*, i8* }` while the closure-literal
// codegen spelled the identical type `{ R(i8*, P…)*, i8* }`, so a
// conditional whose arms were a returned closure and a literal one was
// rejected:
//
//   error: the '?' branches yield values of different types
//          ('{ i64 (i8*, i64)*, i8* }' vs '{ i64(i8*, i64)*, i8* }')
//
// — two spellings of one type, reported as a mismatch with no hint
// that the only difference was a space. `extract_fn_ptr_return_type`
// scans for that same space, so it quietly missed the unspaced form
// too. Found while writing an MCP transport that picks between an
// auth-wrapping handler and a bare one.

$ `stdlib/core/string.nu`

@ wrap ( @ i i ) f → ( @ i i ) { ^ \ i x → i { ^ + 100 ( f x ) } }

@ apply ( @ i i ) f i x → i { ^ ( f x ) }

@ main → i {
    : ( @ i i ) inc \ i x → i { ^ + x 1 }

    // Returned closure vs. closure literal in the two arms.
    : ( @ i i ) a ? T ( wrap inc ) \ i x → i { ^ + x 9 }
    : ( @ i i ) b ? F ( wrap inc ) \ i x → i { ^ + x 9 }
    ( nurl_print ( nurl_str_int ( a 1 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( b 1 ) ) ) ( nurl_print `\n` )

    // …and the same mix passed straight into a call.
    ( nurl_print ( nurl_str_int
    ( apply ? T ( wrap inc ) \ i x → i { ^ + x 9 } 5 ) ) )
    ( nurl_print `\n` )
    ^ 0
}
