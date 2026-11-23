// map: §7.6 | A2 | runs-clean | - | AGORA-953 guard: a join bound by `:` in an inner block whose lent arm reads a value of the outer block (`: e ? c outer ( mk )  = t e`): nothing dies first, nothing to copy
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : String outer ( mk )
    : b c > ( string_len t ) 3
    ? > ( string_len t ) 0 {
        : String e ? c outer ( mk )
        = t e
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
