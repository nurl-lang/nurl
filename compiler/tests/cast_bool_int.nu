// cast_bool_int.nu — regression for the `# i <bool>` widening fix.
//
// A boolean (i1) source must ZERO-extend when cast to a wider int, so
// `# i true` is 1 (not -1). Before the fix gen_cast emitted `sext i1`,
// which sign-extended true to -1 — harmless for `!= 0` callers but it
// broke every predicate documented as "→ 1" (is_digit / is_alpha and
// the char.nu family). This pins the canonical 1/0 result directly.
//
// Determinism: pure arithmetic, no clock/socket/env.

$ `stdlib/core/char.nu`

@ ck s label i got i want → v {
    ( nurl_print label )
    ( nurl_print ? == got want ` ok = ` ` MISMATCH = ` )
    ( nurl_println_int got )
}

@ main → i {
    : i c 65  // 'A'

    // Direct bool-expression casts.
    ( ck `cmp_true  ` # i >= c 10 1 )
    ( ck `cmp_false ` # i >= c 100 0 )
    ( ck `and_true  ` # i & >= c 10 <= c 100 1 )
    ( ck `and_false ` # i & >= c 100 <= c 100 0 )
    ( ck `or_true   ` # i | >= c 100 <= c 100 1 )
    ( ck `or_false  ` # i | >= c 100 >= c 200 0 )
    ( ck `not_true  ` # i ! == c 0 1 )

    // The existing char.nu predicates now return canonical 1, not -1.
    ( ck `is_alpha  ` ( is_alpha 65 ) 1 )
    ( ck `is_digit  ` ( is_digit 53 ) 1 )
    ( ck `is_space  ` ( is_space 32 ) 1 )
    ( ck `is_alnum  ` ( is_alnum_us 95 ) 1 )

    ^ 0
}
