// diag_cmp_enum_int.nu — comparing an enum against a bare number.
// `== c 7` emitted `icmp eq %Color %r4, 7` — invalid IR only clang
// reported, three build stages later; the tag is not a number without
// an explicit conversion.
: | Color { Red Green Blue }

@ main → i {
    : Color c Green
    ? == c 7 { ^ 1 } {}
    ^ 0
}
