// slice_struct_in_a_struct_field_released_with_its_holder: `: W { H h i k }` with `H { [String names i n }`: the holder's release frees the inner struct's slice and its Strings
// main 3358873a: invalid LLVM IR (extractvalue of a struct as its slice). AGORA-869: runs clean, LSan clean; agora #848.
// map: §7.6 | A2 | runs-clean | - | agora #848: a slice struct held in another struct's field
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

: H { [String names i n }
: W { H h i k }

@ mk i n → H { ^ @ H { [String | ( string_from `a name long enough for the heap buffer, yes` ) ( string_from `another name long enough for the heap too` )] n } }

@ main → i {
    : W w @ W { ( mk 2 ) 1 }
    ( nurl_println_int . . w h n )
    ^ 0
}
