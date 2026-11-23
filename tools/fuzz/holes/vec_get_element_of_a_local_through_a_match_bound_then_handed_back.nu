// map: §7.6 | A2 | rejected | - | AGORA-953 (agora #242 twin): a `vec_get` element of a local Vec through a `??`, bound by `:` then handed back: refused as the unbound form is
// twin of tools/fuzz/holes/drop_vec_get_local_match.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v @ D { ( string_from `element string long enough for a heap buffer` ) } )
    : __el ?? ( vec_get [D] v 0 ) { T d → d F → @ D { ( string_from `fresh string long enough for a heap buffer` ) } }
    ^ __el
}

@ main → i {
    : D a ( pick T )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
