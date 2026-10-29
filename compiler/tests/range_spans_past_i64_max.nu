// range_spans_past_i64_max.nu — ranges whose span does not fit an i64.
// Each looped for ever before (found in the stdlib hole hunt of
// 2026-10-28): rand_range's `to - from` wrapped negative and its rejection
// loop never accepted, and range_step / iter_range_step's `k + step`
// wrapped back below `to`, so the walk never ended (range_step's Vec grew
// until memory ran out). The runner's timeout holds them.

$ `stdlib/core/vec.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ b ok T
    : ~ i k 0
    ~ < k 64 {
        : i r ( rand_range -2 9223372036854775807 )
        ? | < r -2 >= r 9223372036854775807 { = ok F } {}
        : i q ( rand_range -9223372036854775807 9223372036854775807 )
        ? >= q 9223372036854775807 { = ok F } {}
        = k + k 1
    }
    ? ok { ( nurl_println `rand_range in range` ) } { ( nurl_println `rand_range OUT of range` ) }
    : ( Vec i ) up ( range_step 0 9223372036854775807 4611686018427387904 )
    ( nurl_println_int ( vec_len [i] up ) )
    : ( Vec i ) down ( range_step 0 -9223372036854775807 -4611686018427387904 )
    ( nurl_println_int ( vec_len [i] down ) )
    ( nurl_println_int ( iter_count [i] ( iter_range_step 0 9223372036854775807 4611686018427387904 ) ) )
    ( nurl_println_int ( iter_count [i] ( iter_range_step 0 -9223372036854775807 -4611686018427387904 ) ) )
    // ordinary ranges are unchanged
    ( nurl_println_int ( vec_len [i] ( range_step 0 10 3 ) ) )
    ( nurl_println_int ( iter_count [i] ( iter_range_step 10 0 -3 ) ) )
    ^ 0
}
