// diag_slice_element_store_while_iterating.nu — a `~` loop over a slice
// reads each element out of the slice's buffer, and an element store drops
// the element it replaces: storing into the slice the loop walks releases
// what the loop may be reading (docs/MEMORY.md §2.5). Refused when the slice
// owns its elements, as `vec_put` on the Vec a loop walks is; a slice of
// plain data is unaffected (slice_element_store_in_loops.nu).
$ `stdlib/core/string.nu`

: Table { [String rows i n }

@ direct → i {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )]
    ~ x a {
        = . a 0 ( string_from `a long enough string to be on the heap, new` )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}

@ by_field → i {
    : ~ Table g @ Table { [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )] 2 }
    ~ x . g rows {
        = . . g rows 1 ( string_from `a long enough string to be on the heap, new` )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}

@ by_index_expression → i {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )]
    : ~ i k 0
    ~ x a {
        = . a k ( string_from `a long enough string to be on the heap, new` )
        ( nurl_println ( string_data x ) )
        = k + k 1
    }
    ^ 0
}

@ main → i {
    ( direct ) ( by_field ) ( by_index_expression )
    ^ 0
}
