// csv_sum — parse an embedded grid of integers separated by ',' and ';'
// (manual atoi over a char scan) and print the sum of every number.
$ `stdlib/core/string.nu`

@ main → i {
    : s text `12,3,45;6,78,9;100,2,33`
    : i n ( nurl_str_len text )
    : ~ i sum 0
    : ~ i cur 0
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? & >= c 48 <= c 57 {
            = cur + * cur 10 - c 48
        } {
            = sum + sum cur
            = cur 0
        }
        = i + i 1
    }
    = sum + sum cur
    ( nurl_println_int sum )
    ^ 0
}
