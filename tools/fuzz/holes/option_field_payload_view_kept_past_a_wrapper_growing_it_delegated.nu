// option_field_payload_view_kept_past_a_wrapper_growing_it_delegated: a view of `?? . h o`'s payload kept past `( w2 h )`, where w2 grows h.o's payload by handing \`. h o\` inout to w
// AGORA-832: refused - an inout field argument's edge is the field's own root's (main 7fbdcef9: no edge, empty summary, accepted, heap-use-after-free)
// map: §2.10 | A2 | rejected | - | AGORA-832
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hh { ? ( Vec i ) o }

@ w inout ? ( Vec i ) o → v {
    ?? o { T q → { : ~ i j 0 ~ < j 1000 { ( vec_push [i] q j ) = j + j 1 } } F → {} }
}

@ w2 inout Hh h → v { ( w . h o ) }

@ main → i {
    : ~ Hh h @ Hh { @ ?( Vec i ) { T ( vec_new [i] ) } }
    ?? . h o {
        T q → {
            ( vec_push [i] q 65 )
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( w2 h )
            ( nurl_println_int ( slice_at [i] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
