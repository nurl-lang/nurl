// string_param_viewed_into_a_field_path_holder: agora #337 — the holder is passed as a field path (`( repoint . h w b )`): the struct it is a field of is read after the String ends.
// Closed: a field path argument names its root as the holder (agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String argument viewed into a holder passed as a field path
$ `stdlib/core/string.nu`

: W { s v }
: H { W w i n }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ H h @ H { @ W { `literal` } 0 }
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( repoint . h w b )
    }
    ( nurl_println . . h w v )
    ^ 0
}
