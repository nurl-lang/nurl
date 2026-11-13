// diag_dup_variant_cross_enum.nu — the same variant name in two
// enums. Variant names are file-scope constants: a bare `X` names ONE
// enum's tag, so a second enum declaring it would get the first one's
// number, silently wrong. (While each variant was a global `@X` this
// also emitted two definitions of it — an error only clang reported,
// location-free.)
: | A { X Y }
: | B { Z X }

@ main → i {
    : B b X
    ^ 0
}
