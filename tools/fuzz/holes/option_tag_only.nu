// option_tag_only: an option literal that gives only its tag (`@ ?( Vec i ) { T }`) left its payload zero bytes: the arm bound a Vec with no control block, and vec_push wrote through null. A result's `{ T }` or `{ F }` did the same to its value or error.
// Closed: outside `unsafe` a wrap literal gives the value its tag names when zero is not a value of its type (gen_agg_lit, __wrap_tl_part).
// ASan: SEGV in vec_push (main).
// map: §6.2 | B | rejected | h184 | option literal with tag only leaves Vec payload zero; push through null
$ `stdlib/core/vec.nu`

@ main → i {
    : ?( Vec i ) o @ ?( Vec i ) { T }
    ?? o {
        T v → {
            ( vec_push [i] v 1 )
            ( nurl_println_int ( vec_len [i] v ) )
        }
        F → {}
    }
    ^ 0
}
