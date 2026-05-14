: | Json {
    JNull
    JBool b
    JNum i
    JStr s
}

@ json_to_str Json val → s {
    ?? val {
        JNull → `null`
        JBool b → ?b `true` `false`
        JNum n → ( nurl_str_int n )
        JStr s → s
    }
}

@ json_is_truthy Json val → b {
    ?? val {
        JNull → F
        JBool b → b
        JNum n → != n 0
        JStr s → != ( nurl_str_len s ) 0
    }
}

@ main → i {
    ( nurl_print `JSON type system test...\n` )

    : Json a @ Json { JNull }
    : Json b @ Json { JBool T }
    : Json c @ Json { JNum 42 }
    : Json d @ Json { JStr `hello` }
    : Json e @ Json { JBool F }
    : Json f @ Json { JNum 0 }

    ( nurl_print `null  → ` ) ( nurl_print ( json_to_str a ) )
    ( nurl_print `  truthy: ` ) ( nurl_print ? ( json_is_truthy a ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `true  → ` ) ( nurl_print ( json_to_str b ) )
    ( nurl_print `  truthy: ` ) ( nurl_print ? ( json_is_truthy b ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `42    → ` ) ( nurl_print ( json_to_str c ) )
    ( nurl_print `  truthy: ` ) ( nurl_print ? ( json_is_truthy c ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `hello → ` ) ( nurl_print ( json_to_str d ) )
    ( nurl_print `  truthy: ` ) ( nurl_print ? ( json_is_truthy d ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `false → ` ) ( nurl_print ( json_to_str e ) )
    ( nurl_print `  truthy: ` ) ( nurl_print ? ( json_is_truthy e ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `0     → ` ) ( nurl_print ( json_to_str f ) )
    ( nurl_print `  truthy: ` ) ( nurl_print ? ( json_is_truthy f ) `yes` `no` )
    ( nurl_print `\n` )

    ^ 0
}
