// diag_cmp_enum_cross.nu — '==' between values of two different enums.
// The emitted icmp mixed `%Color` and `%Fruit` — invalid IR only clang
// saw; had it assembled, it would have compared unrelated variant sets
// by tag.
: | Color { Red Green Blue }
: | Fruit { Apple Pear }

@ main → i {
    : Color c Green
    : Fruit x Pear
    ? == c x { ^ 1 } {}
    ^ 0
}
