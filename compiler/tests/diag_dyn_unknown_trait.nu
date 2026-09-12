// diag_dyn_unknown_trait.nu — '%Name' in a type position where Name is
// not a declared trait.
//
// Every other type position runs the declared-type check; the dynamic
// trait object did not. parse_type_dyn checks object safety only when the
// trait is already known — so a forward-referenced signature does not fail
// before its declaration is scanned — and an UNKNOWN name fell through
// both that and check_type_known, which skipped `%dyn.<Trait>` outright on
// the claim that parse_type_dyn had already validated it.
//
// The result was a reference to `%dyn.Speaker`, a type nothing defines:
// exit 0 from nurlc, rejected by clang with no NURL location. A value of
// the type could not exist in any case — `( dyn Speaker v )` already
// rejects an undeclared trait at construction.
: Dog { i pitch }

@ describe %Speaker s → i {
    ^ 0
}

@ main → i {
    : Dog d @ Dog { 3 }
    ^ . d pitch
}
