// view_field_of_a_loop_element_read_after_what_it_views_grew: agora #492 — `~ w ws { grow line  read . w a }`, ws a `( Vec W )` of structs of views of line
// Closed: a view-class `~` loop element is a borrow of what the container's elements view, as `: s v ( vec_at ws k )` is (agora #492).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #492: `~ w ws { grow line  read . w a }`, ws a `( Vec W )` of structs of views of line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s a }

@ main → i {
    : String line ( string_from `a line long enough for a heap buffer` )
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { ( string_data line ) } )
    ~ w ws {
        : ~ i k 0
        ~ < k 64 { ( string_push_str line ` and a long tail, so the buffer moves` ) = k + k 1 }
        ( nurl_println . w a )
    }
    ^ 0
}
