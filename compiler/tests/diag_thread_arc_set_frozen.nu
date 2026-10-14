// arc_set in safe code (h213). An Arc's payload is frozen once made
// (docs/MEMORY.md §6.5): every clone reads it without a lock, so
// replacing it in place races them. arc_set is `unsafe`, but an
// `unsafe` function is one whose BODY is raw — calling one needs no
// marking (spec §3.3d) — so the call itself is what is refused, as the
// raw-memory primitives are, and the diagnostic names the replacements:
// a fresh Arc, an Rc, or a Locked and its locked_set.
$ `stdlib/std/arc.nu`

@ main → i {
    : ( Arc i ) a ( arc_new [i] 1 )
    ( arc_set [i] a 2 )
    ^ ( arc_get [i] a )
}
