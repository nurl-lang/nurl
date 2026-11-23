// map: §7.6 | A2 | runs-clean | - | AGORA-956 guard: a `??` over a `vec_get` of a parameter, bound by `:` then handed back, stays accepted
// AGORA-956: the caller owns the Vec, so the element handed back is its lend, not a local's
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd → D { ^ @ D { ( string_from `element string long enough for a heap buffer` ) } }

@ pick ( Vec D ) v → D {
    : e ?? ( vec_get [D] v 0 ) { T d → d F → ( mkd ) }
    ^ e
}

@ main → i {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( mkd ) )
    : D a ( pick v )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
