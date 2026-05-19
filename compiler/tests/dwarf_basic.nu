// dwarf_basic.nu — regression target for DWARF debug-info emission.
//
// This file is dual-purpose:
//  1. As an entry in compiler/tests/, it exercises straightforward
//     codegen (a function with locals + a print) and contributes to
//     the baseline diff like every other .nu test.
//  2. As the input to tools/dwarf_test.sh, it provides a known set of
//     source lines and local names the gdb-batch harness can assert
//     against. Do not reformat or reorder without updating that
//     harness — line numbers below are load-bearing for it.

@ square i n → i {
    : i sq * n n
    ^ sq
}

@ main → v {
    : i x 7
    : i y ( square x )
    ( nurl_print ( nurl_str_int y ) ) ( nurl_print `\n` )
}
