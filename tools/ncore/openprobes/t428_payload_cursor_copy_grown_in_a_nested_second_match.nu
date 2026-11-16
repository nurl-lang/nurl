// map: §2.10 | A2 | rejected | - | agora #428: a view of an option payload taken in one `??` arm, kept while a nested second `??` grows a `: ~` copy of the payload
$ `stdlib/core/string.nu`

: H { String name }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    ?? oh {
        T q → {
            : s v ( string_data . q name )
            ?? oh { T r → { : ~ H c r ( string_push_str . c name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} }
            ( nurl_println v )
        }
        F → {}
    }
    ^ 0
}
