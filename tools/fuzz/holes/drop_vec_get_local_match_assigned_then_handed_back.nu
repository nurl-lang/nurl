// map: §7.6 | A2 | rejected | - | AGORA-956: the same element handed out of a `??` over the call, assigned by `=` to a `: ~` binding then handed back
// AGORA-956 (closed): refused (main 3f08626b: accepted, heap-use-after-free under ASan)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd → D { ^ @ D { ( string_from `element string long enough for a heap buffer` ) } }

@ pick b c → D {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( mkd ) )
    : ~ D e ( mkd )
    = e ?? ( vec_get [D] v 0 ) { T d → d F → ( mkd ) }
    ^ e
}

@ main → i {
    : D a ( pick T )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
