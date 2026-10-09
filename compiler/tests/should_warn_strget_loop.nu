// should_warn_strget_loop.nu — walking a string with nurl_str_get in a loop
// is quadratic in its length, and nurlc says so.
//
// nurl_str_get bounds-checks by measuring the string from its start to the
// index on every call, so a loop over a string bound outside it re-measures
// the prefix once per byte. The warning names the O(1) form. What it lets
// through is pinned here too: a fixed index (O(index), not a scan) and a
// string bound inside the loop (each pass measures a fresh one anyway).
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

@ count_nl s src → i {
    : i n ( nurl_str_len src )
    : ~ i k 0
    : ~ i c 0
    ~ < k n {
        ? == ( nurl_str_get src k ) 10 { = c + c 1 } {}
        = k + k 1
    }
    ^ c
}

// The fix the warning points at: same answers, O(1) per byte.
@ count_nl_slice s src → i {
    : ( Slice u ) src_v ( slice_of_str src )
    : i n ( slice_len [u] src_v )
    : ~ i k 0
    : ~ i c 0
    ~ < k n {
        ? == ( slice_byte src_v k ) 10 { = c + c 1 } {}
        = k + k 1
    }
    ^ c
}

// Not flagged: a fixed index.
@ first_byte_thrice s src → i {
    : ~ i k 0
    : ~ i acc 0
    ~ < k 3 { = acc + acc ( nurl_str_get src 0 ) = k + k 1 }
    ^ acc
}

// Not flagged: the string is bound inside the loop.
@ fresh_each_pass s src → i {
    : ~ i k 0
    : ~ i acc 0
    ~ < k 3 {
        : s line ( nurl_str_cat src `` )
        = acc + acc ( nurl_str_get line k )
        = k + k 1
    }
    ^ acc
}

@ main → v {
    ( nurl_println ( nurl_str_int ( count_nl `a\nb\nc\n` ) ) )
    ( nurl_println ( nurl_str_int ( count_nl_slice `a\nb\nc\n` ) ) )
    ( nurl_println ( nurl_str_int ( first_byte_thrice `abc` ) ) )
    ( nurl_println ( nurl_str_int ( fresh_each_pass `abc` ) ) )
    // Past the end reads 0 either way.
    ( nurl_println ( nurl_str_int ( slice_byte ( slice_of_str `ab` ) 5 ) ) )
}
