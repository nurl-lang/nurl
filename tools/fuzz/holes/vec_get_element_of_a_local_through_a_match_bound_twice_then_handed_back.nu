// map: §7.6 | A2 | rejected | - | AGORA-953 (CodeRabbit on github#2189): a non-copyable `??` over a local Vec's `vec_get`, bound by `:`, bound again by `: e2 __el`, then handed back: the second binding keeps the join's lend records, refused as the first is
// Was a heap-use-after-free under ASan on github#2189's first head.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v @ D { ( string_from `element string long enough for a heap buffer` ) } )
    : __el ?? ( vec_get [D] v 0 ) { T d → d F → @ D { ( string_from `fresh string long enough for a heap buffer` ) } }
    : D e2 __el
    ^ e2
}

@ main → i {
    : D a ( pick T )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
