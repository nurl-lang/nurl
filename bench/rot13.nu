// rot13 — ROT13 every lowercase letter of an embedded string and print
// the sum of the resulting byte values. Character-level string scan.
$ `stdlib/core/string.nu`

@ main → i {
    : s text `the quick brown fox jumps over the lazy dog and then the slow purple turtle naps`
    : i n ( nurl_str_len text )
    : ~ i sum 0
    : ~ i i 0
    ~ < i n {
        : i ch ( nurl_str_get text i )
        : ~ i out ch
        ? & >= ch 97 <= ch 122 { = out + 97 % + - ch 97 13 26 } {}
        = sum + sum out
        = i + i 1
    }
    ( nurl_print_int sum )
    ^ 0
}
