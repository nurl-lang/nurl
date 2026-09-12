// diag_match_option_nonexhaustive.nu — a '??' over an option with no
// 'F' arm and no wildcard.
//
// The grammar states one rule for all three scrutinee kinds: "every
// variant must be covered OR a '_' wildcard arm must be present". An enum
// spelling of this mistake has been rejected for years. An option and a
// result were not: check_exhaustive looks the variants up by enum NAME, in
// a `__variants` entry that only a user enum has, so an option or result
// scrutinee fell straight through the loop.
//
// What the uncovered path produced is `undef`. The join reads
// `phi i64 [ %r8, %arm_2 ], [ undef, %next_3 ]`, so `?? o { T v → v }`
// over a None yields whatever happened to be in the register — not a zero,
// and not the same value twice.
@ maybe i a → ?i {
    ^ @ ?i { F }
}

@ main → i {
    : ?i o ( maybe 1 )
    : i v ?? o { T n → n }
    ( nurl_print_int v )
    ^ 0
}
