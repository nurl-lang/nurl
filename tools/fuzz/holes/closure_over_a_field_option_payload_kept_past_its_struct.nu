// closure_over_a_field_option_payload_kept_past_its_struct: agora #483 — a closure over the payload of a struct's option field read in place (`?? . p o`) is kept past the struct's block and run after
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a field option's payload kept past its struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { ? String o i n }

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : P p @ P { @ ?String { T ( string_from `a payload freed with its struct at the end of the block` ) } 1 }
        ?? . p o {
            T y → { = f \ → i { ^ ( strlen ( string_data y ) ) } }
            F → {}
        }
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
