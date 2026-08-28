// histogram — count each digit 0-9 in an embedded string and print the
// single highest count. Array-indexed tally over a char scan.
$ `stdlib/core/string.nu`

@ main → i {
    : s text `314159265358979`
    : i n ( nurl_str_len text )
    : *i hist # *i ( malloc * 10 8 )
    : ~ i j 0
    ~ < j 10 {
        = . hist j 0
        = j + j 1
    }
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? & >= c 48 <= c 57 {
            : i d - c 48
            = . hist d + . hist d 1
        } {}
        = i + i 1
    }
    : ~ i maxc 0
    : ~ i k 0
    ~ < k 10 {
        : i v . hist k
        ? > v maxc { = maxc v } {}
        = k + k 1
    }
    ( nurl_println_int maxc )
    ( free hist )
    ^ 0
}
