$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ ordered b arm → v {
    ; { ( nurl_print `earliest\n` ) }
    ; {
        : ( Vec i ) values ( vec_new [i] )
        ( vec_push [i] values 42 )
        ; { ( vec_free [i] values ) ( nurl_print `inner first\n` ) }
        ; {
            ; { ( nurl_println_int . ( vec_data [i] values ) 0 ) }
            ( nurl_print `inner second\n` )
        }
        ? arm { ; { ( nurl_print `taken child\n` ) } } {}
        : s owned ( nurl_str_cat `child-` `owned` )
        ; { ( nurl_print owned ) ( nurl_print `\n` ) }
        ( nurl_print `outer\n` )
    }
    ; { ( nurl_print `latest\n` ) }
    ( nurl_print `body\n` )
}

@ loop_children → v {
    ; {
        : ~ i k 0
        ~ < k 3 {
            ; { ( nurl_print `loop child once\n` ) }
            = k + k 1
        }
        ? F { ; { ( nurl_print `unreached\n` ) } } {}
        ( nurl_print `loop outer\n` )
    }
}

@ early → i {
    ; { ; { ( nurl_print `early child\n` ) } }
    ^ 7
}

@ closure_in_cleanup → v {
    ; {
        : ( @ i i ) twice \ i value → i { ^ * value 2 }
        ( nurl_println_int ( twice 21 ) )
    }
}

@ main → i {
    ( ordered T )
    ( ordered F )
    ( loop_children )
    ( nurl_println_int ( early ) )
    ( closure_in_cleanup )
    ^ 0
}
