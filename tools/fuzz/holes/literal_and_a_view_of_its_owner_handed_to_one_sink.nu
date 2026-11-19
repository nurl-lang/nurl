// literal_and_a_view_of_its_owner_handed_to_one_sink: AGORA-926 — `( use2 @ S { b 0 } sv )`: b taken into a literal a sink grows, and sv, a view of b, handed beside it
// AGORA-926 (closed): refused (main 58ab3032: accepted)
// map: §2.10 | A2 | rejected | - | AGORA-926: a literal taking b and a view of b handed to one sink that grows it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf i n }

@ use2 sink S x ( Slice i ) v → v {
    : ~ S y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] v 1 ) )
}

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Slice i ) sv ( slice_from_vec [i] b )
    ( use2 @ S { b 0 } sv )
    ^ 0
}
