// view_element_of_a_loop_read_after_what_it_views_got_a_new_value: agora #492 — `~ v ws { = line fresh  ( nurl_println v ) }`, ws a `( Vec s )` of views of line
// Closed: a view-class `~` loop element is a borrow of what the container's elements view, as `: s v ( vec_at ws k )` is (agora #492).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #492: `~ v ws { = line fresh  ( nurl_println v ) }`, ws a `( Vec s )` of views of line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ String line ( string_from `a line long enough for a heap buffer` )
    : ( Vec s ) ws ( vec_new [s] )
    ( vec_push [s] ws ( string_data line ) )
    ~ v ws {
        = line ( string_from `a fresh line, the old one is released here` )
        ( nurl_println v )
    }
    ^ 0
}
