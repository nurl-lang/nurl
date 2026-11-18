// option_field_payload_view_taken_after_a_growing_callee_runs_clean: `?? . h o`'s payload grown by `( w . h o )`, the view taken after the call
// AGORA-832 guard: accepted - the view sees the moved buffer
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
            ( w . h o )
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( nurl_println_int ( slice_at [i] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
