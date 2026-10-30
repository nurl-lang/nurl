// fresh_string_in_slice_literal: a fresh string as an element of a slice literal: the slice owns its buffer, not the raw strings in it, so the string leaked.
// map: §2.13 | A2 | rejected | h140 | fresh string element of slice literal leaks
$ `stdlib/core/string.nu`

@ fill → i {
    : [s xs [s | ( nurl_str_cat `a` `bc` ) `d`]
    ^ . xs 1
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 3 { = t + t ( fill ) = k + k 1 }
    ( nurl_print_int t ) ( nurl_print `\n` )
    ^ 0
}
