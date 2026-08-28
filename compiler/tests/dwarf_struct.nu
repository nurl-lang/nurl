// dwarf_struct.nu — regression target for DWARF Phase 6 composite types.
//
// Dual-purpose like dwarf_basic.nu:
//  1. As an entry in compiler/tests/, it exercises straightforward
//     struct codegen (named struct, multi-field literal, dotted reads)
//     and contributes to the baseline diff like every other .nu test.
//  2. As the second input to tools/dwarf_test.sh, it provides a known
//     set of struct field names so the gdb-batch harness can assert
//     `ptype` + `print` over a composite value resolve to NURL names
//     instead of falling back to the raw i64 placeholder.
//
// Line numbers below are load-bearing for the harness — do not
// reformat or reorder.

: Point { i x i y }

@ origin → Point {
    : Point p @ Point { 3 7 }
    ^ p
}

@ main → v {
    : Point p ( origin )
    ( nurl_println_int . p x )
    ( nurl_println_int . p y )
}
