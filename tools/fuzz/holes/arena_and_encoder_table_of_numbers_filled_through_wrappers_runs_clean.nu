// arena_and_encoder_table_of_numbers_filled_through_wrappers_runs_clean: agora #383 — yoloe's tokenizer shape: a struct of an arena and a `( HashMap s i )` keyed by views of its elements, filled through a `map_set` wrapper by a helper handed the struct, then returned
// Control for agora #383 (map_set replacing a number drops nothing).
// map: §2.10 | A2 | runs-clean | - | agora #383: yoloe's tokenizer shape: a struct of an arena and a `( HashMap s i )` keyed by views of its elements, filled through a `map_set` wrapper by a helper handed the struct, then returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`
: Tab { ( Vec String ) arena ( HashMap s i ) enc }
@ tab_set ( HashMap s i ) m s key i val → v {
    ( map_set [s i] m key val \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}
@ tab_get ( HashMap s i ) m s key → i {
    ^ ?? ( map_get [s i] m key \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } ) { T v → v F _ → -1 }
}
@ tab_put ( Vec String ) arena ( HashMap s i ) enc String key i id → v {
    ( vec_push [String] arena key )
    : String k ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( tab_set enc ( string_data k ) id )
}
@ tab_fill Tab t → v {
    : ~ i j 0
    ~ < j 40 {
        : String key ( string_from `a key long enough to live on the heap #` )
        ( string_push_int key j )
        ( tab_put . t arena . t enc key j )
        = j + j 1
    }
}
@ tab_make → Tab {
    : Tab t @ Tab { ( vec_new [String] ) ( map_new [s i] ) }
    ( tab_put . t arena . t enc ( string_from `the first key, long enough for the heap` ) 100 )
    ( tab_fill t )
    ^ t
}
@ main → i {
    : Tab t ( tab_make )
    : String out ( string_new )
    ( string_push_int out ( tab_get . t enc `the first key, long enough for the heap` ) )
    ( string_push_int out ( tab_get . t enc `a key long enough to live on the heap #39` ) )
    ( nurl_println ( string_data out ) )
    ^ 0
}
