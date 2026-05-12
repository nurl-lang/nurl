// Test: string_index_of → ?i and string_to_float → ?f
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`

@ show_idx s haystack s needle → v {
    : String h ( string_from haystack )
    : ? i r ( string_index_of h needle )
    ( nurl_print haystack )
    ( nurl_print ` / ` )
    ( nurl_print needle )
    ( nurl_print ` -> ` )
    ? ( opt_is_some [i] r ) {
        ( nurl_print `some ` )
        ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] r 0 ) ) )
    } {
        ( nurl_print `none` )
    }
    ( nurl_print `\n` )
    ( string_free h )
}

@ show_float s raw → v {
    : String t ( string_from raw )
    : ? f r ( string_to_float t )
    ( nurl_print `'` )
    ( nurl_print raw )
    ( nurl_print `' -> ` )
    ? ( opt_is_some [f] r ) {
        ( nurl_print `some ` )
        ( nurl_print ( nurl_str_float ( opt_unwrap_or [f] r 0.0 ) ) )
    } {
        ( nurl_print `none` )
    }
    ( nurl_print `\n` )
    ( string_free t )
}

@ main → i {
    ( show_idx `hello world` `world` )   // some 6
    ( show_idx `hello world` `lo` )      // some 3
    ( show_idx `hello world` `xyz` )     // none
    ( show_idx `hello world` `` )        // some 0
    ( show_idx `` `x` )                  // none

    ( show_float `3.14` )                // some 3.14
    ( show_float `-2.5` )                // some -2.5
    ( show_float `+1` )                  // some 1
    ( show_float `0.5` )                 // some 0.5
    ( show_float `.5` )                  // some 0.5
    ( show_float `1.` )                  // some 1
    ( show_float `1e3` )                 // some 1000
    ( show_float `-1.5e2` )              // some -150
    ( show_float `2E-1` )                // some 0.2
    ( show_float `` )                    // none
    ( show_float `-` )                   // none
    ( show_float `.` )                   // none
    ( show_float `1e` )                  // none
    ( show_float `1e+` )                 // none
    ( show_float `abc` )                 // none
    ( show_float `1.2.3` )               // none
    ( show_float `12x` )                 // none
    ^ 0
}
