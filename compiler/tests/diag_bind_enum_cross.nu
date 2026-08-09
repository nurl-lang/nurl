// diag_bind_enum_cross.nu — binding a value of one enum to a
// declaration of another. Both lower to `{ i64 }`, so the store was
// invalid IR only clang saw — and one silent reinterpretation away
// (Pear's tag arriving as Green) had the layouts been merged.
: | Color { Red Green Blue }
: | Fruit { Apple Pear }

@ main → i {
    : Fruit x Pear
    : Color c x
    ^ 0
}
