// H437: `sort_by` with a comparator that is not consistent (it says
// "less" for nearly every pair): the Hoare partition's scans stopped only
// at an element the comparator ranked against the pivot, which the
// median-of-three sentinels guarantee for a consistent comparator only,
// so `i` ran past the end of the Vec.
// Closed: each scan also stops at its range's end — a branch in the scan's
// body, which measured no slower than the unguarded scan.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/sort.nu`

// inconsistent: 1 only for (1,0) so run detection stops at 2, else -1
@ bad i a i b → i {
    ? & == a 1 == b 0 { ^ 1 } {}
    ^ -1
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 100 { ( vec_push [i] v k ) = k + k 1 }
    ( sort_by [i] v \ i a i b → i { ^ ( bad a b ) } )
    ( nurl_print `done\n` )
    ^ 0
}
