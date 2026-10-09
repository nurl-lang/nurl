// H72: a map value borrow; a callee replaces that key and drops the old value; the borrow is read.
$ `stdlib/std/hashmap.nu`
$ `stdlib/core/string.nu`

@ replace ( HashMap s String ) m → v {
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }
    ?? ( map_set [s String] m `a` ( string_from `replaced` ) hs es ) { T old → { ( string_free old ) } F → {} }
}

@ main → i {
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }
    : ( HashMap s String ) m ( map_new [s String] )
    ( map_set [s String] m `a` ( string_from `a long value string on the heap` ) hs es )
    ?? ( map_get [s String] m `a` hs es ) { T e → { ( replace m ) ( nurl_println_int ( string_len e ) ) } F → {} }
    ^ 0
}
