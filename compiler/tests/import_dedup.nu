// import_dedup.nu — regression for `$`-import deduplication.
//
// Three distinct dedup paths in the compiler that this test exercises:
//
//   1. Direct duplicate: same path imported twice.
//   2. Diamond: stdlib/std/fmt.nu transitively imports
//      stdlib/core/string.nu and stdlib/core/vec.nu; we ALSO import
//      both directly. Without dedup, the second pass would re-emit
//      every `@`-fn / `%`-type from those files and the link would
//      fail with `redefinition of …` errors.
//   3. Path-normalisation: `./stdlib/...` and `stdlib/...` are the
//      same file. The compiler strips leading `./` before keying into
//      the dedup table — added 2026-05-15 alongside this test.
//
// Pre-fix (string-keyed dedup, no normalisation): case 3 emitted
// `error: redefinition of type %String` from clang during linking.
// Post-fix: compile + link clean, output matches the baseline.

$ `stdlib/std/fmt.nu`
$ `stdlib/core/string.nu`
$ `./stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `./stdlib/core/vec.nu`

@ main → i {
    // Exercise the string + vec API surfaces that arrived via every
    // route above, to prove the deduplicated decls remain callable.
    : String s ( string_with_cap 16 )
    ( string_push_str s `dedup=` )
    ( string_push_str s `ok` )
    ( nurl_print ( string_data s ) )
    ( nurl_print `\n` )
    ( string_free s )

    : ( Vec i ) v ( vec_with_cap [i] 4 )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [i] v 3 )
    ( nurl_print `vec_len=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
    ( nurl_print `\n` )
    ( vec_free [i] v )

    ^ 0
}
