// diag_match_or_unknown_variant.nu — an or-pattern alternative that
// names no variant of the enum being matched.
//
// The FIRST name in a pattern has been checked against the enum for
// years. The alternatives after `|` were not, and emitted a load of a
// global nothing defines — an undefined symbol at link time, reported
// by clang with no NURL location.

: | Color { Red Green Blue }

@ main → i {
    : Color c @ Color { Green }
    ?? c {
        Red | Nope → {}
        _ → {}
    }
    ^ 0
}
