// loop_over_a_field_option_payload_read_after_a_helper_clears_it: agora #482 — `?? . h o { T r → ~ x r { … } }`; a helper given `h` (`inout`) clears that payload's rows through the field; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a field option's payload read after a helper clears it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ? ( Vec String ) o i n }

@ wipe_h inout H h → v { = . h o @ ?( Vec String ) { F } }

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : ~ H h @ H { @ ?( Vec String ) { T t } 0 }
    : ~ H g @ H { @ ?( Vec String ) { F } 0 }
    : ( @ v ) clr \ → v {}
    ?? . h o {
        T r → {
            ~ x r {
                ( wipe_h h )
                ( nurl_println ( string_data x ) )
                break
            }
        }
        F → {}
    }
    ^ 0
}
