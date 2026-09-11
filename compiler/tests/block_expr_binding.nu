// block_expr_binding.nu — a block is an expression, so a binding may be
// initialised by one. The grammar has said so since v1
// (`let_stmt = ':' '~'? type? IDENT expr`, `expr = … | block_expr`), and
// the assignment path has always honoured it (`= x { 7 }` stores 7).
//
// The binding path did not: it skipped the initialiser token by token up
// to the FIRST '}' and returned `undef` without ever defining the name.
// The declaration vanished silently — a later use reported an undefined
// identifier at the USE site, and an unused one compiled clean with the
// binding simply missing. Nested braces were worse: the scan stopped
// inside the block and the remainder was re-parsed as statements.

: Counter { i n i max }

@ twice i n → i { ^ * n 2 }

@ main → i {
    // Tail value only.
    : i a { 7 }
    // Statements first; the block's own locals stay inside it.
    : i b {
        : i inner 20
        + inner 1
    }
    // A nested block inside the initialiser: the old scan stopped at its
    // '}' and misparsed the rest of the statement.
    : i c {
        : i n { 5 }
        * n 2
    }
    // Mutable binding whose initialiser ends in a call.
    : ~ i d { ( twice 8 ) }
    = d + d 1
    // A block initialiser in an inner scope, and one that reads an outer
    // binding — the value is the tail expression, not the declaration.
    : i e {
        : i base a
        + base 100
    }
    // Control for diag_block_binding_escape.nu: a closure bound through a
    // block expression is fine as long as what it captures by pointer
    // outlives the block. `ctr` is a function-level binding, so the
    // closure's referent is this frame, not the initialiser's.
    : ~ Counter ctr @ Counter { 0 10 }
    : ( @ v ) bump {
        ( nurl_print `bound\n` )
        \ → v { = . ctr n + . ctr n 1 }
    }
    ( bump )
    ( bump )
    ( nurl_print `a=` ) ( nurl_print ( nurl_str_int a ) ) ( nurl_print `\n` )
    ( nurl_print `b=` ) ( nurl_print ( nurl_str_int b ) ) ( nurl_print `\n` )
    ( nurl_print `c=` ) ( nurl_print ( nurl_str_int c ) ) ( nurl_print `\n` )
    ( nurl_print `d=` ) ( nurl_print ( nurl_str_int d ) ) ( nurl_print `\n` )
    ( nurl_print `e=` ) ( nurl_print ( nurl_str_int e ) ) ( nurl_print `\n` )
    ( nurl_print `ctr=` ) ( nurl_print ( nurl_str_int . ctr n ) ) ( nurl_print `\n` )
    ^ 0
}
