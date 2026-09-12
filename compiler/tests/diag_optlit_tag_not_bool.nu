// diag_optlit_tag_not_bool.nu — field 0 of an option literal is the TAG,
// and it is a bool.
//
// Every payload slot of an option or result literal is checked against
// its declared type — there are five separate diagnostics for the ways a
// payload can disagree with one. The TAG slot was checked against
// nothing, so `@ ?i { 1 3 }` emitted
// `insertvalue { i1, i64 } undef, i64 1, 0`: invalid IR, reported by
// clang three build stages later with no NURL location.
//
// The spelling that reaches it in practice is not a wrong tag but a
// MISSING one. `@ ?f { 3 }` puts the payload in field 0 and every value
// shifts one slot left, which is exactly what deleting a single `T` from
// an option literal does — and is how the token-deletion sweep's clang
// oracle found this one.

@ main → i {
    : ?i o @ ?i { 1 3 }
    ^ 0
}
