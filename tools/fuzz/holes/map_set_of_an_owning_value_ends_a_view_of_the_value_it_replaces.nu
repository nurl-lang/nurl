// map_set_of_an_owning_value_ends_a_view_of_the_value_it_replaces: agora #383 — `map_set` on a `( HashMap s String )` replacing the String a view was taken of: the replace rule below is for values that own nothing
// main 87895b72: rejected already.
// map: §2.10 | A2 | rejected | - | agora #383: `map_set` on a `( HashMap s String )` replacing the String a view was taken of: the replace rule below is for values that own nothing
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`

@ main → i {
    : ( HashMap s String ) m ( map_new [s String] )
    ( map_set [s String] m `k` ( string_from `a value long enough to live on the heap` ) \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
    : String v0 ?? ( map_get [s String] m `k` \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } ) { T v → v F _ → ( string_new ) }
    : s view ( string_data v0 )
    ( map_set [s String] m `k` ( string_from `a replacement long enough for the heap` ) \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
    ( nurl_println view )
    ^ 0
}
