// H711: agora #178 — a struct field (a String inside) of a parameter handed back through a `?`, the argument reassigned (struct_field_of_a_struct_param_through_a_cond).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: Q { P p i k }

@ part Q q b c → P { ^ ? c . q p @ P { ( mk ) 0 } }

@ main → i {
    : ~ Q q @ Q { @ P { ( mk ) 1 } 2 }
    : P t ( part q T )
    = q @ Q { @ P { ( mk ) 3 } 4 }
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
