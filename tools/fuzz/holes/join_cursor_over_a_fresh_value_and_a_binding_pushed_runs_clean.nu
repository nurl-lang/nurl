// join_cursor_over_a_fresh_value_and_a_binding_pushed_runs_clean: `: ~ String cur ? == k 1 ( string_from … ) a  ( vec_push [String] d cur )`
// AGORA-840 item 3 guard: accepted, runs clean - the fresh value goes to d, a keeps its own (clean on main too)
// map: §2.12 | A2 | runs-clean | - | AGORA-840
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }

@ keep inout Bag b String s → v { ( vec_push [String] . b items s ) }

@ main → i {
    : String a ( string_from `a string long enough to be on the heap for certain` )
    : String b ( string_from `another string long enough to be on the heap too` )
    : ( Vec String ) d ( vec_new [String] )
    : ~ Bag g @ Bag { ( vec_new [String] ) }
    : i k ( nurl_str_len `x` )
    : ~ String cur ? == k 1 ( string_from `a fresh string long enough to be on the heap now` ) a
    ( vec_push [String] d cur )
    ( nurl_println ( string_data ( vec_at [String] d 0 ) ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
