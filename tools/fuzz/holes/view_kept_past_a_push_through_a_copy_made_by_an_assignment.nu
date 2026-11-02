// view_kept_past_a_push_through_a_copy_made_by_an_assignment: agora #440 — `= c ( id b )` over an owned c, then c grown while a holder views b
// Closed: a String or Vec borrowed from bindings of its own type, by `=` as by `:`, is a copy of one of their handles whole (`cborrow`) (bck_view_end_via, agora #440).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #440: `= c ( id b )` over an owned c, then c grown while a holder views b
$ `stdlib/core/string.nu`

: W { s v }

@ id String a → String { ^ a }

@ main → i {
    : String b ( string_from `the b string, short` )
    : ~ W w @ W { ( string_data b ) }
    : ~ String c ( string_from `a c string, long enough for the heap` )
    = c ( id b )
    ( string_push_str c ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println . w v )
    ^ 0
}
