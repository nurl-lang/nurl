// map: §7.6 | A2 | runs-clean | - | AGORA-959: a `:` join reading an inner struct's struct field, handed to an `inout` struct parameter, is the parameter's own copy
// AGORA-959: as for a String (main c4c0f350 refused it)
$ `stdlib/core/string.nu`

: W { String s }
: H { W w i n }

@ mkw → W { ^ @ W { ( string_from `hello world, long enough for a heap buffer` ) } }

@ f inout W t b c → v {
    : H p @ H { ( mkw ) 1 }
    : W x . p w
    : y ? c . p w ( mkw )
    = t y
}

@ main → i {
    : ~ W t ( mkw )
    ( f t T )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
