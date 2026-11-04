// view_of_an_element_field_kept_across_a_loop_replacing_it_through_its_loop_element: agora #350 — a view of `. e name` (`e` read out of `ps` with vec_at), then `~ x ps { = . x name … }`; the view read after the loop
// Closed: a field replaced through a `~` loop's element is replaced in an element of what the loop iterates (`fe_`; agora #350, #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #350: a view of an element's field kept across a loop that replaces the field through its loop element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ( Vec P ) ps ( vec_new [P] )
    ( vec_push [P] ps @ P { ( string_from `an old name, replaced inside the loop` ) 1 } )
    : P e ( vec_at [P] ps 0 )
    : s v ( string_data . e name )
    ~ x ps { = . x name ( string_from `a new name, long enough for the heap` ) }
    ( nurl_println v )
    ^ 0
}
