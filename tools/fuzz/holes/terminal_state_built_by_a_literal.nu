// terminal_state_built_by_a_literal: `( term_raw_disable @ TermState { -1 ( vec_new [u] ) } )`:
// tcsetattr read a whole struct termios through the data pointer of an
// empty Vec.
// Closed: TermState is `raw` (only term_raw_enable makes one), and
// term_raw_disable restores nothing from a `saved` shorter than a termios.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h501 | `( term_raw_disable @ TermState { -1 ( vec_new [u] ) } )`: tcsetattr read a whole struct termios through the data pointer of an empty Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/std/term.nu`

@ main → i {
    ( term_raw_disable @ TermState { -1 ( vec_new [u] ) } )
    ^ 0
}
