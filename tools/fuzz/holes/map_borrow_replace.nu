// map_borrow_replace: a map value borrow; map_set replaces that key and the old value is dropped; the borrow is read.
// map: StmtT.assign | A1 | rejected | h73 | map value borrow; map_set replaces key, old value dropped; borrow read
$ `stdlib/std/hashmap.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }
    : ( HashMap s String ) m ( map_new [s String] )
    ( map_set [s String] m `a` ( string_from `a long value string on the heap` ) hs es )
    ?? ( map_get [s String] m `a` hs es ) {
        T e → {
            ?? ( map_set [s String] m `a` ( string_from `replaced` ) hs es ) { T old → { ( string_free old ) } F → {} }
            ( nurl_println_int ( string_len e ) )
        }
        F → {}
    }
    ^ 0
}
