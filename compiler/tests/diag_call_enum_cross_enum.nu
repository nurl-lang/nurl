// diag_call_enum_cross_enum.nu — passing a value of one enum where a
// DIFFERENT enum is declared. Both lower to an i64 tag, so the call
// used to assemble and the callee read this value's tag as the OTHER
// enum's variants (here: Pear's tag 1 arriving as Green).
: | Color { Red Green Blue }
: | Fruit { Apple Pear }

@ show Color c → i {
    ^ 0
}

@ main → i {
    : Fruit x Pear
    ^ ( show x )
}
