// inner_scope_slice_named_like_an_outer_one_releases_its_buffer: `: [i xs …` in an arm, a loop body and a nested arm while an outer `xs` slice is in scope.
// Closed: owned slices are listed by their storage, one entry per binding (__slice_key). By name the arm's `xs` was the outer one's entry: the arm's end took it for a slice declared outside the arm and released nothing (agora #653; closures went the same way in #614).
// main 0b31ade: accepted; LeakSanitizer: the inner slice's buffer, once per run of the scope.
// map: §7.1 | A2 | runs-clean | - | agora #653: a slice bound in an inner scope under the name of an outer slice is released by nobody — the owned-slice list is by name
@ sum [i xs → i {
    : ~ i t 0
    ~ w xs { = t + t w }
    ^ t
}

@ g i n → i {
    : [i xs [i | 1 2 3 n]
    : ~ i t 0
    ? > n 0 { : [i xs [i | 7 8 9 n n] = t + t ( sum xs ) } {}
    : ~ i k 0
    ~ < k 3 {
        : [i xs [i | k k k]
        ? > k 1 { : [i xs [i | 100 k] = t + t ( sum xs ) } {}
        = t + t ( sum xs )
        = k + k 1
    }
    ^ + t ( sum xs )
}

@ main → i {
    ( nurl_println_int ( g 2 ) )
    ( nurl_println_int ( g 0 ) )
    ^ 0
}
