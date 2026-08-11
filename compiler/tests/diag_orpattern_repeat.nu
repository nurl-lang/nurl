// diag_orpattern_repeat.nu — a variant listed twice in one or-pattern.
//
// This shared its text with the plain-arm duplicate check in the same
// function. Both said "a match arm already covers variant" — true of
// the arm case, and a poor description of an alternative repeated
// inside a single pattern.
: | D { N S E W }

@ main → i {
    : D d @ D { N }
    : i r ?? d { N | S | N → 1 E → 2 W → 3 }
    ^ r
}
