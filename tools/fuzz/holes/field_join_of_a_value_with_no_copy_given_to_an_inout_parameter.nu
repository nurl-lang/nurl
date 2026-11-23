// map: §7.6 | A2 | rejected | - | AGORA-959 guard: a field join of a `% Drop` struct handed to an `inout` parameter stays refused
// AGORA-959: there is no copy to give it, so codegen marks nothing
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d i n }

@ mkd → D { ^ @ D { ( string_from `hello world, long enough for a heap buffer` ) } }

@ f inout D t b c → v {
    : H p @ H { ( mkd ) 1 }
    : y ? c . p d ( mkd )
    = t y
}

@ main → i {
    : ~ D t ( mkd )
    ( f t T )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
