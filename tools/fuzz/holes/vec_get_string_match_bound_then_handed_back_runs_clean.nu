// map: §7.6 | A2 | runs-clean | - | AGORA-956 guard: a `??` over a `vec_get` of a local Vec of String, bound by `:` then handed back, is copied and runs clean
// AGORA-956: a String can be copied, so the lend of the local is copied at the `^`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick b c → String {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `element string long enough for a heap buffer` ) )
    : e ?? ( vec_get [String] v 0 ) { T d → d F → ( string_from `fresh` ) }
    ^ e
}

@ main → i {
    : String a ( pick T )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
