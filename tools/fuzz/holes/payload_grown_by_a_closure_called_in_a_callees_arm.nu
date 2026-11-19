// map: §2.11 | A2 | rejected | - | AGORA-428: a view of an option payload kept while a callee hands its payload to a closure that grows it
// AGORA-428 (closed by AGORA-842 part 1): refused - the view of the payload, named past its arm, points into the option, which the growth ends (main 34edc2a1: accepted)
$ `stdlib/core/string.nu`

: H { String name }

@ each inout ? H o ( @ v H ) f → v { ?? o { T q → { ( f q ) } F → {} } }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ?? oh { T q → ( string_data . q name ) F → `none` }
    : ( @ v H ) f \ H h → v { ( string_push_str . h name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) }
    ( each oh f )
    ( nurl_println v )
    ^ 0
}
