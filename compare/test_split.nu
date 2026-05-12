$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `a,b,c` )
    : ( Vec String ) v ( string_split s `,` )
    ( nurl_print `Len: ` ) ( nurl_print ( nurl_str_int ( vec_len [String] v ) ) ) ( nurl_print `\n` )
    
    : ~ i i 0
    ~ < i ( vec_len [String] v ) {
        : ? String s_opt ( vec_get [String] v i )
        ?? s_opt {
            T ss → { ( nurl_print ( string_data ss ) ) ( nurl_print `\n` ) }
            F → {}
        }
        = i + i 1
    }
    
    : (@ v String) drop \ String e → v { ( string_free e ) }
    ( vec_free_with [String] v drop )
    ( string_free s )
    ^ 0
}
