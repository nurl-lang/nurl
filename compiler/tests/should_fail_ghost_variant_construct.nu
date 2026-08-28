// should_fail_ghost_variant_construct.nu — critic A7, ghost-variant
// half, construction side. `Strng` is a typo for a type name, so the
// enum parser reads it as a separate variant and `V` declares no
// payload; the literal below then supplies one. Pre-diagnostic this
// emitted broken IR (`store  %r14, * %r15` — clang rejected far from
// the cause). Now a hard error at the literal.
$ `stdlib/core/string.nu`

: | E { Nil V Strng W i }

@ main → i {
    : E e @ E { V ( string_from `x` ) }
    ?? e {
        V s → { ( nurl_print `v\n` ) }
        W n → { ( nurl_println_int n ) }
        Strng → { ( nurl_print `ghost\n` ) }
        Nil → { ( nurl_print `nil\n` ) }
    }
    ^ 0
}
