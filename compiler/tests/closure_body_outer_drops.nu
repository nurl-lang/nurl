// closure_body_outer_drops.nu — a closure body must not drop the ENCLOSING
// frame's owned values.
//
// A closure literal is lifted to a separate `define`, but it is emitted in the
// middle of the enclosing function's emission and inherits its symbol table.
// `gen_closure_expr` shadowed the slice and closure-env rosters with empty
// lists for exactly that reason — and left the other three visible:
// `__owned_strings__`, `__owned_struct_fields__` and `__user_drops__`.
//
// So a `^` inside the closure body ran gen_ret, gen_ret drained those lists,
// and the lifted function ended with the OUTER frame's drop battery:
//
//     define i64 @__closure_1(i8* %__env, i64 %x) {
//       …
//       %r7 = load %DH, %DH* %r2        ; %r2 is main's alloca — not here
//       call void @drop__DH(%DH %r7)
//
// clang rejected that as "use of undefined value". Had the register resolved
// it would have been a use-after-scope plus a second drop of a value the outer
// frame drops again on its own exit. Only a closure body with an explicit `^`
// reached gen_ret, so an expression-bodied literal looked fine — which is why
// this survived: the shape needs an owned value live at the point the literal
// appears AND a `^` in its body.
//
// Pinned below: a `% Drop` value, an owned String and an owned struct field,
// each live across a `^`-bodied closure literal — the drop must fire exactly
// once, in the frame that owns the value.
//
// Expected output:
//   noclosure=6 drops=1
//   withclosure=8 drops=2
//   string=2
//   field=7 drops=3

$ `stdlib/core/string.nu`

: ~ i g_drops 0

: DH { i tag }

% Drop ( DH ) { @ drop DH h → v { = g_drops + g_drops 1 } }

: Holder { String name }

@ noclosure i n → i {
    : DH h @ DH { n }
    ^ * n 2
}

@ withclosure i n → i {
    : DH h @ DH { n }
    : ( @ i i ) cl \ i x → i { ^ * x 2 }
    ^ ( cl n )
}

// An owned String live across the literal: the closure body must not free it.
@ withstring i n → i {
    : String s ( string_new )
    ( string_push_char s 65 )
    ( string_push_char s 66 )
    : ( @ i i ) cl \ i x → i { ^ + x n }
    : i r ( cl ( nurl_str_len ( string_data s ) ) )
    ( string_free s )
    ^ - r n
}

// An owned struct FIELD live across the literal, plus a %Drop value, so all
// three rosters are non-empty at once.
@ withfield i n → i {
    : DH h @ DH { n }
    : Holder hold @ Holder { ( string_new ) }
    ( string_push_char . hold name 67 )
    : ( @ i i ) cl \ i x → i { ^ + x 6 }
    : i r ( cl ( nurl_str_len ( string_data . hold name ) ) )
    // String is a manually-managed handle (docs/MEMORY.md §7.4) — released
    // here so the test stays LeakSanitizer-clean on the fuzzer's ASan leg.
    ( string_free . hold name )
    ^ r
}

@ main → i {
    ( nurl_print `noclosure=` )
    ( nurl_print ( nurl_str_int ( noclosure 3 ) ) )
    ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) )
    ( nurl_print `\n` )

    ( nurl_print `withclosure=` )
    ( nurl_print ( nurl_str_int ( withclosure 4 ) ) )
    ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) )
    ( nurl_print `\n` )

    ( nurl_print `string=` )
    ( nurl_print ( nurl_str_int ( withstring 9 ) ) )
    ( nurl_print `\n` )

    ( nurl_print `field=` )
    ( nurl_print ( nurl_str_int ( withfield 5 ) ) )
    ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) )
    ( nurl_print `\n` )
    ^ 0
}
