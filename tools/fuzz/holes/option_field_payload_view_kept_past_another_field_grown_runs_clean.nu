// option_field_payload_view_kept_past_another_field_grown_runs_clean: a view of `?? . h o`'s payload kept past `( grow . h other )`, which grows a different field of h
// AGORA-832 guard: accepted - the payload is lent out of h.o, so another field's growth leaves it alone
// map: §2.10 | A2 | runs-clean | - | AGORA-832
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hh { ? ( Vec i ) o ( Vec i ) other }

@ w inout ? ( Vec i ) o → v {
    ?? o { T q → { : ~ i j 0 ~ < j 1000 { ( vec_push [i] q j ) = j + j 1 } } F → {} }
}

@ rd ? ( Vec i ) o → i {
    ?? o { T q → { ^ ( vec_len [i] q ) } F → { ^ 0 } }
}

@ grow inout ( Vec i ) v → v { : ~ i j 0 ~ < j 1000 { ( vec_push [i] v j ) = j + j 1 } }

@ main → i {
    : ~ Hh h @ Hh { @ ?( Vec i ) { T ( vec_new [i] ) } ( vec_new [i] ) }
    ?? . h o {
        T q → {
            ( vec_push [i] q 65 )
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( grow . h other )
            ( nurl_println_int ( slice_at [i] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
