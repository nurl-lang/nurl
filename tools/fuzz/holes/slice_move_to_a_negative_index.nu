// slice_move_to_a_negative_index: `( slice_move [i] s 0 -6 8 )`: the range test compared
// `to + n` with the length, and -6 + 8 is in range, so the move wrote 48
// bytes before the slice.
// Closed: each start is tested, unsigned, against the room `n` leaves; a
// negative one panics as an index past the end does.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h441 | `( slice_move [i] s 0 -6 8 )`: the range test compared `to + n` with the length, and -6 + 8 is in range, so the move wrote 48 bytes before the slice.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 8 { ( vec_push [i] v k ) = k + k 1 }
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( slice_move [i] s 0 -6 8 )
    ^ 0
}
