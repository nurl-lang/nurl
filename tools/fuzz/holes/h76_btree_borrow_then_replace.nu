// H76: a btree_get borrow; btree_set replaces that key and the old value is dropped; the borrow is read.
$ `stdlib/std/btree.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i i i ) cmp \ i a i b → i { ^ - a b }
    : ( BTree i String ) m ( btree_new [i String] )
    ( btree_set [i String] m 1 ( string_from `a long value string on the heap` ) cmp )
    ?? ( btree_get [i String] m 1 cmp ) {
        T e → {
            ?? ( btree_set [i String] m 1 ( string_from `replacement` ) cmp ) { T old → { ( string_free old ) } F → {} }
            ( nurl_println_int ( string_len e ) )
        }
        F → {}
    }
    ^ 0
}
