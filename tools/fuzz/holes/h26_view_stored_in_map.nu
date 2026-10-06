// H26: a view of a String stored as a map key; the String is freed; the map is read.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`

@ main → i {
    : ( HashMap s i ) m ( map_new [s i] )
    : String k ( string_from `a key long enough to live on the heap, 64 bytes or so` )
    : ?i _o ( map_set [s i] m ( string_data k ) 1 \ s t → i { ^ ( hash_string t ) } \ s a s b → b { ^ ( eq_string a b ) } )
    ( string_free k )
    ?? ( map_get [s i] m `a key long enough to live on the heap, 64 bytes or so` \ s t → i { ^ ( hash_string t ) } \ s a s b → b { ^ ( eq_string a b ) } ) {
        T v → { ( nurl_println_int v ) }
        F → { ( nurl_println `missing` ) }
    }
    ^ 0
}
