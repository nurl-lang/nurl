// diag_cast_struct_literal.nu — '#' used where '@' builds a literal.
//
// A SINGLE-FIELD struct used to slip through: the "is this a registered
// struct" test read the key for field index 1 — the SECOND field — so
// every struct with one field failed it and the literal was accepted
// silently. A single-field struct is the newtype wrapper, one of the
// commonest shapes there is, and a two-field struct was caught all
// along, which is what made the gap invisible.
: S { i a }

@ main → i {
    : S s # S { 1 }
    ^ 0
}
