// A generic called from inside another generic's body, with no template
// of that name anywhere in the import closure, is reported at the call:
// "no generic of that name". It used to type the call as i64 and report a
// mismatch against the binding it initialised, pointing away from the
// missing `$` import (stdlib/std/rc.nu calling mem_replace without
// importing stdlib/core/mem.nu).
: P { i n }

@ f [A] sink A x → A {
    : A y ( no_such_generic [A] x )
    ^ y
}

@ main → i {
    : P a ( f [P] @ P { 1 } )
    ^ . a n
}
