// borrow_strict_nested_alias.nu — strict-mode exclusive access, for a
// read that is not a bare identifier and not a direct field read
// either (docs/MEMORY.md §2.4 / §2.9).
//
// `( bump_by c ( peek c ) )` reads `c` inside a nested call while the
// same `c` is mutably borrowed by the same call. Strict mode already
// reported the `. c n` spelling of exactly this, so reporting one and
// not the other made the depth of the expression decide the verdict.
// A per-argument log of the names actually loaded — nested calls
// included — is what the check now consults.
//
// Default `--borrowck` accepts every line here on purpose: a sibling
// read is a snapshot taken before the callee runs, and
// `( grow v ( vec_len v ) )` is ordinary correct code. Only the
// documented over-flagging mode reports it.
//
// Two positive cases (nested call, nested call under an operator) +
// one negative control (a different binding).

: Counter { i n i tag }

@ peek Counter c → i { ^ . c n }

@ twice i n → i { ^ * n 2 }

@ bump_by inout Counter a i b → v {
    = . a n + . a n b
}

@ main → i {
    : ~ Counter c @ Counter { 3 0 }
    : ~ Counter d @ Counter { 9 0 }

    // POSITIVE — `c` is mutably borrowed and read one call deep.
    ( bump_by c ( peek c ) )

    // POSITIVE — the same read, two calls deep and under an operator.
    ( bump_by c + ( twice ( peek c ) ) 1 )

    // CONTROL — the read names a different binding.
    ( bump_by c ( peek d ) )

    ^ . c n
}
