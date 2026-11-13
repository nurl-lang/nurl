// A value block whose tail is its own fresh binding, spelled like an outer
// binding that was moved, is accepted (agora #629): the walk judges the
// tail by the block's binding, not the moved outer one. As a let's value,
// and as a sink argument after the moved outer one. Each value is released
// once.
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eat2 sink String x sink String y → i { ^ + ( string_len x ) ( string_len y ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : String e { : i n ( eat s ) : ~ String s ( string_from `inner string long enough for a heap buffer` ) s }
    ( nurl_println ( string_data e ) )
    : ~ String t ( string_from `second outer string long enough for heap` )
    : i r ( eat2 t { : String t ( string_from `second inner string long enough for heap` ) t } )
    ( nurl_println_int r )
    ^ 0
}
