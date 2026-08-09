// struct_enum_field_ops.nu — enum-typed struct fields, the LEGAL
// forms. `@ S { Green }` used to emit the bare i64 tag into the
// `%Color` slot (invalid IR only clang saw — the wrap was missing at
// the struct-literal site while binding/assign/return already had it).
// Locks: variant in a struct literal, a `?`-join of variants in a
// struct literal, an enum-typed field ASSIGNED a variant, reading the
// field back into an enum binding, comparing it, and matching on it.
: | Color { Red Green Blue }
: S { Color c i n }

@ main → i {
    : S s @ S { Green 1 }
    ? == . s c Green { ( nurl_print `lit_variant\n` ) } {}
    : i k 5
    : S t @ S { ? > k 3 Blue Red 2 }
    ? == . t c Blue { ( nurl_print `lit_join\n` ) } {}
    : ~ S u @ S { Red 3 }
    = . u c Green
    ? == . u c Green { ( nurl_print `field_assign\n` ) } {}
    : Color c . u c
    ? != c Red { ( nurl_print `field_read\n` ) } {}
    ?? c {
        Red → { ( nurl_print `match_red\n` ) }
        Green → { ( nurl_print `match_green\n` ) }
        Blue → { ( nurl_print `match_blue\n` ) }
    }
    ^ 0
}
