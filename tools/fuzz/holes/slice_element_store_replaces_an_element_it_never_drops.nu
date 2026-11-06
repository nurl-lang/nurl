// slice_element_store_replaces_an_element_it_never_drops: agora #485 — an element store into a slice of Strings (`= . sl k ( string_from … )`, `= . sl 0 . h s`) put the value in without releasing the element it replaced, and a fresh value stored there was owned by nothing; a field stored there was a second name for the field's buffer.
// Closed: a store into a slice that owns its elements drops the element it replaces (mem_emit_slice_slot_drop) and puts in a value of the slice's own: a fresh one moves in, a borrowed one is copied (mem_slice_store_val); a binding is refused (diag_slice_element_store_of_a_binding).
// main (before this PR): LeakSanitizer, the replaced literal's Strings and the stored one.
// map: §7.1 | A2 | runs-clean | - | agora #485: an element store into a slice of Strings never dropped the replaced element, and a fresh stored value leaked (leak)
$ `stdlib/core/string.nu`

: H { String s i n }

@ main → i {
    : H h @ H { ( string_from `a struct field stored over a slice element, heap sized` ) 1 }
    : String b ( string_from `a copy of this binding is stored over a slice element` )
    : i k 1
    {
        : [String sl [String | ( string_from `the slice literal's first string, replaced` ) ( string_from `the slice literal's second string, replaced` ) ( string_from `the third, replaced by a copy` )]
        = . sl k ( string_from `a fresh string stored over the second element` )
        = . sl 0 . h s
        = . sl 2 ( string_clone b )
        ~ x sl { ( nurl_println ( string_data x ) ) }
    }
    ( nurl_println ( string_data . h s ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
