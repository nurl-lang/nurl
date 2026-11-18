// join_cursor_handed_to_a_keeping_fn_runs_clean: `: ~ String cur ? == k 1 a b  ( keep g cur )`, keep pushing its parameter into a field
// AGORA-840 item 3: runs clean - the call is handed a copy, and a and b drop their own (main 393d7473: leaked under strict LSan)
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
    : ~ String cur ? == k 1 a b
    ( keep g cur )
    ( nurl_println ( string_data ( vec_at [String] . g items 0 ) ) )
    ^ 0
}
