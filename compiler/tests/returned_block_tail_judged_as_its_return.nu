// A value block handed back by `^` is judged as its tail binding's return
// (agora #663): a block whose tail is a block naming a parameter or
// lending a local element hands back a copy; a block-local owner, and a
// view of a parameter the caller keeps, are handed back as they are.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string` ) }

@ mkv i c → ( Vec String ) {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mk c ) )
    ^ v
}

@ f String p → String { ^ { { p } } }

@ g i c → String { ^ { { : ( Vec String ) u ( mkv c ) : String t ( vec_at [String] u 0 ) t } } }

@ h i c → String { ^ { : String t ( mk c ) t } }

@ k String p → s { ^ { : s d ( string_data p ) d } }

@ main → i {
    : String a ( mk 1 )
    : String b ( f a )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data ( g 1 ) ) )
    ( nurl_println ( string_data ( h 1 ) ) )
    ( nurl_println ( k a ) )
    ^ 0
}
