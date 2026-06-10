// dwarf_ptr_struct.nu — regression for pointer-to-struct DI types.
//
// Dual-purpose like dwarf_struct.nu:
//  1. As an entry in compiler/tests/, it exercises heap struct codegen
//     (`# *T ( nurl_alloc Z T )`, dotted writes/reads through the
//     pointer) and contributes a normal golden.
//  2. As the third input to tools/dwarf_test.sh it locks two fixes:
//     a `*Struct` local used to emit `!DILocalVariable(type: !0)` —
//     undefined metadata that failed the whole `--g` build at the
//     clang stage (dangling-else in dbg_type_id_for's fallback chain),
//     and pointer locals now get a real DW_TAG_pointer_type wrapping
//     the pointee's composite, so gdb renders `print *p` field-by-name.
//
// Line numbers below are load-bearing for the harness — do not
// reformat or reorder.

: Cell { i v i w }

@ main → i {
    : *Cell p # *Cell ( nurl_alloc Z Cell )
    = . p v 7
    = . p w 9
    : i out . p v
    ( nurl_print ( nurl_str_int out ) )
    ( nurl_print `\n` )
    ( nurl_free # s p )
    ^ 0
}
