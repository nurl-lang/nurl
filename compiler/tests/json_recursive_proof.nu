// json_recursive_proof.nu — proof-of-concept that a self-referential
// enum payload `( Vec Json )` actually compiles. If this links and runs
// the full json.nu module rests on solid ground.
//
// Expected output:
//   tag=2
//   tag=4 inner_count=2

$ `stdlib/core/vec.nu`

: | Json {
    JNull
    JBool b
    JNum i
    JStr s
    JArr ( Vec Json )
}

@ tag_of Json j → i {
    ^ ?? j {
        JNull → 0
        JBool _ → 1
        JNum _ → 2
        JStr _ → 3
        JArr _ → 4
    }
}

@ main → i {
    : Json a @ Json { JNum 42 }
    ( nurl_print `tag=` )
    ( nurl_print ( nurl_str_int ( tag_of a ) ) )
    ( nurl_print `\n` )

    : ( Vec Json ) v ( vec_new [Json] )
    ( vec_push [Json] v @ Json { JNum 1 } )
    ( vec_push [Json] v @ Json { JNum 2 } )

    : Json arr @ Json { JArr v }
    ( nurl_print `tag=` )
    ( nurl_print ( nurl_str_int ( tag_of arr ) ) )

    // pluck the inner Vec back out and report its size
    ?? arr {
        JArr inner → {
            ( nurl_print ` inner_count=` )
            ( nurl_print ( nurl_str_int ( vec_len [Json] inner ) ) )
        }
        _ → ( nurl_print ` (no arr)` )
    }
    ( nurl_print `\n` )
    ^ 0
}
