// field_view_outlives_replace: a binding read out of a struct field (`: String b . s name`) is a view of the value the field holds, and assigning the field (`= . s name …`) dropped that value under it: printing `b` afterwards read freed memory.
// Closed: a store that replaces a field hands the old value to a binding in scope that was read out of that field and still holds it (its drop flag is set, compared by buffer identity at run time) instead of dropping it — the binding owns it from there and drops it at its scope's end.
// main (before this PR): AddressSanitizer, heap-use-after-free.
// map: §2.10 | A2 | runs-clean | h196 | binding read from struct field outlives reassignment of that field
$ `stdlib/core/string.nu`

: Rec { String name i n }

@ main → i {
    : ~ Rec s @ Rec { ( string_from `the original value, long enough for the heap` ) 2 }
    : String b . s name
    = . s name ( string_from `the replacement value, long enough for the heap` )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data . s name ) )
    ^ 0
}
