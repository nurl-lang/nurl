// map: §2.10 | A2 | rejected | - | AGORA-428: a view of an option payload kept while a callee grows it through a `: ~` copy in its own `??`
// AGORA-428 (closed by AGORA-842 part 1): refused - the view of the payload, named past its arm, points into the option, which the growth ends (main 34edc2a1: accepted)
$ `stdlib/core/string.nu`

: H { String name }

@ grow_o inout ? H o → v { ?? o { T q → { : ~ H c q ( string_push_str . c name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} } }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ?? oh { T q → ( string_data . q name ) F → `none` }
    ( grow_o oh )
    ( nurl_println v )
    ^ 0
}
