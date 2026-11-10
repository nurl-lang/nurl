// slice_element_store_in_loops.nu — the element stores a loop may make
// (agora #545): into a slice of plain data while a `~` loop walks it, into a
// slice of owners from a counter loop, from a loop over another slice, and
// after the loop. (Into the slice of owners the loop itself walks is refused:
// diag_slice_element_store_while_iterating.nu.)
$ `stdlib/core/string.nu`

@ plain_data → i {
    : ~ [i a [i | 1 2 3]
    : ~ i k 0
    ~ x a { = . a k * x 2 = k + k 1 }
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

@ counter_loop → i {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )]
    : ~ i k 0
    ~ < k 2 { = . a k ( string_from `a long enough string to be on the heap, new` ) = k + k 1 }
    ~ x a { ( nurl_println ( string_data x ) ) }
    ^ 0
}

@ over_another → i {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )]
    : [i n [i | 0 1]
    ~ k n { = . a k ( string_from `a long enough string to be on the heap, other` ) }
    ~ x a { ( nurl_println ( string_data x ) ) }
    : [String c [String | ( string_from `a long enough string to be on the heap, c0` )]
    ~ x c { = . a 1 ( string_from ( string_data x ) ) }
    ~ x a { ( nurl_println ( string_data x ) ) }
    ^ 0
}

@ after_the_loop → i {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )]
    ~ x a { ( nurl_println ( string_data x ) ) }
    = . a 0 ( string_from `a long enough string to be on the heap, after` )
    ~ x a { ( nurl_println ( string_data x ) ) }
    ^ 0
}

@ main → i {
    ( plain_data ) ( counter_loop ) ( over_another ) ( after_the_loop )
    ^ 0
}
