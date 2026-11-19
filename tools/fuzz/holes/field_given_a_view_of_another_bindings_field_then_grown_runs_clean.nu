// field_given_a_view_of_another_bindings_field_then_grown_runs_clean: AGORA-926 guard — `= . o v ( slice_from_vec [i] . q buf )` - a field given a view of another binding's field, then the first binding's own field grown: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-926 guard: `= . o v ( slice_from_vec [i] . q buf )` - a field given a view of another binding's field, then the first binding's own field grown: accepted
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    : ( Vec i ) c ( vec_new [i] )
    ( vec_push [i] c 1 )
    ( vec_push [i] c 2 )
    : ( Vec i ) d ( vec_new [i] )
    ( vec_push [i] d 3 )
    ( vec_push [i] d 4 )
    : ( Slice i ) dv ( slice_from_vec [i] d )
    : S q @ S { c dv }
    : ~ S o @ S { b dv }
    = . o v ( slice_from_vec [i] . q buf )
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . o buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . o v 1 ) )
    ^ 0
}
