// ret_struct_owned_transfer.nu — critic A4c: a function returning a
// by-value struct with fresh-owned fields transfers those allocations
// to the caller.
//
// Before this fix two bugs:
//   * `^ @ T { ( cat … ) }` direct-construction return → the field
//     leaked (callee never registered it, caller never registered it).
//   * `^ v` where v is a bound struct → the callee's scope-exit drop
//     freed v's field while the returned-by-value copy still aliased
//     it: a use-after-free in the caller.
//
// The fix gives the callee a skip (it transfers ownership out, never
// drops) and propagates the exact owned-field list so the caller's
// `: T x ( f )` re-registers it — exactly one drop, at the caller's
// scope exit. Propagation composes through `^ ( mk )` call chains and
// reaches through nested struct fields.
//
// Frees are observable under ASan/LSan (run_san_tests.sh); this golden
// locks compile + run + output. The "no double-free" half is locked by
// the san run: if the callee's drop were NOT skipped, the second drop
// would fire there.

$ `stdlib/core/string.nu`

: Inner { s name i n }
: Outer { Inner inner i tag }

// Direct construction return — leaked pre-fix.
@ mk_direct → Inner {
    ^ @ Inner { ( nurl_str_cat `direct-` `owned` ) 1 }
}

// Bound-then-return — use-after-free pre-fix.
@ mk_bound → Inner {
    : Inner v @ Inner { ( nurl_str_cat `bound-` `owned` ) 2 }
    ^ v
}

// Call-chain return — ownership must compose through two levels.
@ mk_chain → Inner {
    ^ ( mk_direct )
}

// Nested owned field reached through an outer struct.
@ mk_nested → Outer {
    ^ @ Outer { @ Inner { ( nurl_str_cat `nested-` `owned` ) 3 } 9 }
}

@ main → i {
    : Inner a ( mk_direct )
    ( nurl_print . a name ) ( nurl_print `\n` )

    : Inner b ( mk_bound )
    ( nurl_print . b name ) ( nurl_print `\n` )

    : Inner c ( mk_chain )
    ( nurl_print . c name ) ( nurl_print `\n` )

    : Outer o ( mk_nested )
    ( nurl_print . . o inner name ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
