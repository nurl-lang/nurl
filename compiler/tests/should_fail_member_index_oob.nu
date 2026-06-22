// should_fail_member_index_oob.nu — an out-of-range integer index into an
// aggregate used to emit an invalid `extractvalue …, N`.
: P { i x i y }

@ main → i { : P p @ P { 1 2 } ^ . p 9 }
