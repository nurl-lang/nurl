// slice_literals_of_copies_constants_and_views_used_in_time_run_clean: a slice literal of a String binding read after the binding is given a new value (the literal copied it), one of a view read after the view itself is given a new value, one of a view read before its source changes, and one of constants
// Closed (agora #930): what a slice literal's elements view it holds, and only that: an element that owns all it holds is copied in and depends on nothing, a view element depends on what it views, not on the binding it was read from.
// main 85a31ca: runs clean (the guard against a fix that refuses these).
// map: §2.13 | A2 | runs-clean | - | agora #930: slice literals of a copied String, of a view later repointed, of a view read before its source changes, and of constants
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `a string long enough for a heap buffer` )
    : [String sa [String | a]
    = a ( string_from `another` )
    ~ e sa { ( nurl_println_int ( string_len e ) ) }
    : String keep ( string_from `a kept source string long enough for a heap buffer` )
    : ~ s w ( string_data keep )
    : [s sw [s | w]
    = w `other`
    ~ e sw { ( nurl_println e ) }
    : ~ String src ( string_from `a changed source string long enough for a heap buffer` )
    : s v ( string_data src )
    : [s sv [s | v `lit`]
    ~ e sv { ( nurl_println e ) }
    = src ( string_from `another` )
    ( nurl_println ( string_data src ) )
    : [s sc [s | `a` `b`]
    ~ e sc { ( nurl_println e ) }
    ^ 0
}
