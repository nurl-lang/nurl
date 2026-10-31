// omitted_enum_payload: an enum literal that leaves a ( Vec i ) payload out zero-initialises it: the match arm bound a Vec with no control block, and vec_push wrote through null.
// Closed: as h180 — outside `unsafe` a payload whose type has no valid zero value is given (gen_agg_lit, __zero_invalid).
// ASan: SEGV in vec_push (main).
// map: §6.2 | B | rejected | h183 | enum literal omits Vec payload: arm binds zero Vec, push writes through null
$ `stdlib/core/vec.nu`

: | Shape { Dot Poly ( Vec i ) }

@ main → i {
    : Shape s @ Shape { Poly }
    ?? s {
        Poly v → {
            ( vec_push [i] v 3 )
            ( nurl_println_int ( vec_len [i] v ) )
        }
        Dot → {}
    }
    ^ 0
}
