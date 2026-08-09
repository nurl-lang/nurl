// enum_slice_ops.nu — a slice of enums, the LEGAL forms. `[Color |
// Red Green Blue]` used to store each variant's bare i64 tag into a
// `%Color` slot — invalid IR only clang saw, so an enum slice literal
// never compiled. Locks: construction from bare variants, the length
// field read, and a foreach whose loop variable compares against a
// variant (the gen_binary tag-compare on a loop-carried enum value).
: | Color { Red Green Blue }

@ main → i {
    : [Color cs [Color | Red Green Blue]
    : i n . cs 1
    ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
    : ~ i greens 0
    ~ val cs {
        ? == val Green { = greens + greens 1 } {}
    }
    ( nurl_print ( nurl_str_int greens ) ) ( nurl_print `\n` )
    ^ 0
}
