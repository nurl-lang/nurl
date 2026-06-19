// words — count words (maximal runs of ASCII letters) in an embedded
// string. A character-level state machine: print only the word count.
$ `stdlib/core/string.nu`

@ is_letter i c → b {
    ^ | & >= c 97 <= c 122 & >= c 65 <= c 90
}

@ main → i {
    : s text `the quick123brown fox, jumps-over the lazy_dog!`
    : i n ( nurl_str_len text )
    : ~ i count 0
    : ~ i inword 0
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? ( is_letter c ) {
            ? == inword 0 {
                = count + count 1
                = inword 1
            } {}
        } {
            = inword 0
        }
        = i + i 1
    }
    ( nurl_print_int count )
    ^ 0
}
