// match_int_literal.nu — regression for the int-literal arm shape
//   ?? value { N → ... _ → ... }
// added 2026-05-18 to gen_match. Covers:
//   * positive / zero / large / negative literals
//   * sized-integer match-value (i32)
//   * wildcard catches the residual
//   * arms returning different kinds of values (string here)

@ classify i n → s {
    ^ ?? n {
        0 → `zero`
        1 → `one`
        2 → `two`
        42 → `meaning`
        -1 → `neg-one`
        65536 → `2^16`
        _ → `other`
    }
}

@ classify_i32 i32 n → s {
    ^ ?? n {
        100 → `c100`
        200 → `c200`
        404 → `c404`
        _ → `c-other`
    }
}

@ main → i {
    ( nurl_print ( classify 0 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify 1 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify 2 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify 5 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify 42 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify -1 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify 65536 ) ) ( nurl_print `\n` )

    ( nurl_print ( classify_i32 # i32 100 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify_i32 # i32 200 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify_i32 # i32 404 ) ) ( nurl_print `\n` )
    ( nurl_print ( classify_i32 # i32 999 ) ) ( nurl_print `\n` )
    ^ 0
}
