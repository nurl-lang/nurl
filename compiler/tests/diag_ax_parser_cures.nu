// diag_ax_parser_cures.nu — a parser error must name the cure.
//
// "expected X" alone is the half that does not help: a reader who knew
// which construct they were in would not have written the mistake. Each
// of these used to say only what was wanted. They now say what was
// FOUND and what the correct form IS, so the next attempt is informed
// rather than another guess.
//
// The text is baselined because the text is the feature.
//
// This file stops at the first error (the parser cannot recover from a
// mangled arm), so it pins the one an agent is most likely to hit: a
// match arm with two expressions and no braces. Its siblings —
// closure bodies, binding order, '@' declarations, field access, impl
// methods, guards, enum names — are covered by the same shape and were
// verified by hand at the same time.
//
// Expected: COMPILE FAIL naming the arm-body rule.

$ `stdlib/core/string.nu`

@ main → i {
    ?? ( string_from `x` ) {
        T s → { ( string_free s ) }
        F e → ( nurl_print `a` ) ( nurl_print `b` )
    }
    ^ 0
}
