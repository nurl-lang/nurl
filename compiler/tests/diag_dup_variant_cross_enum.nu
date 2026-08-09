// diag_dup_variant_cross_enum.nu — the same variant name in two
// enums. Variant names are file-scope constants (each becomes a global
// '@X'), so this emitted two `@X = global i64` definitions — an error
// only clang reported, location-free; and had it linked, every bare
// `X` would resolve to ONE enum's tag, silently wrong for the other.
: | A { X Y }
: | B { Z X }

@ main → i {
    : B b X
    ^ 0
}
