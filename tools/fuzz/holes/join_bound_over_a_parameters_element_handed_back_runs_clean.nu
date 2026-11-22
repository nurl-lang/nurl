// map: §7.6 | A2 | runs-clean | - | AGORA-953 guard: `: D e ?? ( vec_get [D] v 0 ) { … }  ^ e` with v a parameter: the lend is the caller's, so the bound join is handed back as the unbound one is
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick ( Vec D ) v → D {
    : D e ?? ( vec_get [D] v 0 ) { T d → d F → @ D { ( string_from `fresh string long enough for a heap buffer` ) } }
    ^ e
}

@ main → i {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v @ D { ( string_from `element string long enough for a heap buffer` ) } )
    : D a ( pick v )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
