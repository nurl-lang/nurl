// should_fail_ghost_variant_match.nu — critic A7, ghost-variant half.
// `String` here is NOT defined or imported, so the enum parser reads it
// as a SEPARATE variant (parse disambiguation: an unknown ident in
// payload position cannot be a type). The match arm then binds a
// payload from the payload-less `V` — pre-diagnostic this emitted an
// out-of-bounds extractvalue: invalid IR, or a silent garbage read
// when a sibling variant's slot happened to exist. Now a hard error
// naming the variant, the count, and the likely missing-import cause.
: | E { Nil  V String }
@ main → i {
    : E e # E V
    ?? e {
        V s → { ( nurl_print `v\n` ) }
        String → { ( nurl_print `ghost\n` ) }
        Nil → { ( nurl_print `nil\n` ) }
    }
    ^ 0
}
