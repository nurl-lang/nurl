// u8_spelling_ops.nu — the `u8` TYPE SPELLING. llvm_type's ladder had
// `u` → u8 but not `u8` itself, so the documented `u8` spelling fell
// through to the named-type default: every `: u8 x` binding carried
// the phantom type `%u8` (undeclared in the module), surfacing as
// far-away invalid IR at first real use — and nothing in the tree
// used the spelling, so nothing caught it. Locks: binding + cast at
// the u8 spelling, ZERO-extension on widening (200 stays 200, not
// -56), and uitofp on the float conversion.
@ main → i {
    : u8 hi # u8 200
    : i wide # i hi
    ( nurl_print ( nurl_str_int wide ) ) ( nurl_print `\n` )
    : f asf # f hi
    ? > asf 199.0 { ( nurl_print `unsigned_ok\n` ) } {}
    ^ 0
}
