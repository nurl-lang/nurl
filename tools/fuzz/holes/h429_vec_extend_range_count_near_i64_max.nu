// H429: `( vec_extend_range [i] dst src 1 9223372036854775807 )`: the
// clamp tested `start + n > len`, which wraps, so the count stayed huge,
// the grow was skipped, and the copy ran off both buffers.
// Closed: the count is clamped against the room left (`len - start`).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 1 ) ( vec_push [i] src 2 )
    : ( Vec i ) dst ( vec_new [i] )
    ( vec_push [i] dst 7 )
    ( vec_extend_range [i] dst src 1 9223372036854775807 )
    ^ 0
}
