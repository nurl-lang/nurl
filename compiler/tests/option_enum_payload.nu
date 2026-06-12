// option_enum_payload.nu — regression for option-of-enum construction.
//
// `@ ?E { T Variant }` where E is a no-payload (C-style) enum used to
// emit `insertvalue { i1, %E } …, i64 tag, 1` — a bare variant
// evaluates to its i64 tag, but the option's payload slot is the whole
// `%E` aggregate, and clang rejected the type mismatch. gen_agg_lit now
// wraps the tag with `insertvalue %E zeroinitializer, i64 tag, 0` (the
// inverse of the `! T E` tag-extract path). The Result form `! T E`
// always worked because its payload slot is i64; only the option form
// was broken.

: | Color { Red Green Blue }

@ pick i x → ?Color {
    ? == x 1 { ^ @ ?Color { T Red } } {}
    ? == x 2 { ^ @ ?Color { T Green } } {}
    ? == x 3 { ^ @ ?Color { T Blue } } {}
    ^ @ ?Color { F }
}

@ name_of ?Color o → s {
    ?? o {
        T c → ?? c { Red → `red` Green → `green` Blue → `blue` }
        F _ → `none`
    }
}

@ main → i {
    ( nurl_print ( name_of ( pick 1 ) ) ) ( nurl_print ` ` )
    ( nurl_print ( name_of ( pick 2 ) ) ) ( nurl_print ` ` )
    ( nurl_print ( name_of ( pick 3 ) ) ) ( nurl_print ` ` )
    ( nurl_print ( name_of ( pick 9 ) ) ) ( nurl_print `\n` )
    ^ 0
}
