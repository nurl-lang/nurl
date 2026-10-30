// bare_variant_with_payload: a bare variant used as a value (`: Shape s Poly`) is its tag alone, and the payload slots of the enum value it became were undefined: the arm bound a Vec made of whatever bits were there.
// Closed: outside `unsafe` a bare variant is a value only when its payloads are plain numbers or flags (__bare_variant_check).
// ASan: SEGV in vec_push (main).
// map: §6.2 | B | rejected | h185 | bare variant as value leaves Vec payload undefined; arm uses garbage Vec
$ `stdlib/core/vec.nu`

: | Shape { Dot Poly ( Vec i ) }

@ main → i {
    : Shape s Poly
    ?? s {
        Poly v → {
            ( vec_push [i] v 1 )
            ( nurl_println_int ( vec_len [i] v ) )
        }
        Dot → {}
    }
    ^ 0
}
