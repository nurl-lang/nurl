// enum_slice_payload_released_by_the_enum_runs_clean: `: | E { EA [i EB i }` built from a literal, a returned one on one path, in a loop, in a Vec, of Strings, and from an owned slice binding, then matched: the enum releases its slice once
// main: did not compile (the payload's drop read the box as a slice of no type), or the payload leaked.
// map: §7.6 | A2 | runs-clean | - | agora #841: an enum's slice payload is boxed and released by the enum's drop; an owned slice moved into one moves
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }

@ mk → [i { ^ [i | 1 2] }

: | E { EA [i EB i }

: | Gs { GA [String GB i }

@ pick b c → E { ? c { ^ @ E { EA [i | 4 5] } } {} ^ @ E { EB 7 } }

@ wrap → E { : [i q ( mk ) ^ @ E { EA q } }

@ show E e → i { ?? e { EA p → { ^ ( sum p ) } EB n → { ^ n } } ^ 0 }

@ main → i {
    : E a ( pick T )
    : E b ( pick F )
    : E w ( wrap )
    : [i q ( mk )
    : E m @ E { EA q }
    : Gs g @ Gs { GA [String | ( string_from `an element long enough for a heap buffer` )] }
    : ~ ( Vec E ) v ( vec_new [E] )
    ( vec_push [E] v @ E { EA [i | 1 2] } )
    ( vec_push [E] v @ E { EB 3 } )
    : ~ i k 0
    ~ < k 3 { : E e @ E { EA [i | k k] } ( nurl_println_int ( show e ) ) = k + k 1 }
    ?? g { GA p → ( nurl_println_int 1 ) GB n → ( nurl_println_int n ) }
    ( nurl_println_int + + + + ( show a ) ( show b ) ( show w ) ( show m ) ( vec_len [E] v ) )
    ^ 0
}
