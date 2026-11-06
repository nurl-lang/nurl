// slice_literal_returned_bare_never_freed_by_the_caller: agora #485 — a function that hands back a slice literal itself (`^ [ i | 1 2 3 ]`, a fall-off `[ i | … ]`, `^ ? c [ … ] [ … ]`, a forwarder `^ ( mk )`) was not taken to return an owned slice, so the caller's binding never freed its buffer (nor the Strings it now owns); `^ s` with `s` bound to the literal was.
// Closed: gen_ret and the fall-off return publish `__fn_ret_owned__` for a fresh slice (a literal, a join of literals, an owned slice call's result), as for an owned slice binding returned by name.
// main (before this PR): LeakSanitizer, each returned buffer and its Strings.
// map: §7.1 | A2 | runs-clean | - | agora #485: a slice literal handed back bare (`^ [ … ]`, fall-off, join, forwarder) was never freed by the caller (leak)
$ `stdlib/core/string.nu`

@ ints → [i { ^ [i | 1 2 3] }
@ ints_tail → [i { [i | 4 5] }
@ ints_join b c → [i { ^ ? c [i | 6 7] [i | 8] }
@ strs → [String {
    ^ [String | ( string_from `a string in a returned slice literal, heap sized` ) ( string_from `the second string of the returned slice literal` )]
}
@ fwd → [String { ^ ( strs ) }

@ main → i {
    {
        : [i a ( ints )
        : [i b ( ints_tail )
        : [i c ( ints_join T )
        ~ x a { ( nurl_println ( nurl_str_int x ) ) }
        ~ x b { ( nurl_println ( nurl_str_int x ) ) }
        ~ x c { ( nurl_println ( nurl_str_int x ) ) }
    }
    {
        : [String s ( strs )
        : [String f ( fwd )
        ~ x s { ( nurl_println ( string_data x ) ) }
        ~ x f { ( nurl_println ( string_data x ) ) }
    }
    ^ 0
}
