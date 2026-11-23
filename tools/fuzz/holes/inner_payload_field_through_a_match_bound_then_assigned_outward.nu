// map: §7.6 | A2 | runs-clean | - | AGORA-953 (agora #242 twin): a field of an inner block's enum payload through a `??`, bound by `:` then assigned outward: copied on the lent paths
// twin of tools/fuzz/holes/inner_payload_field_through_a_match_assigned_outward.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : G g @ G { V @ P { ( mk ) 1 } }
        : __el ?? g { V p → . p s Nil → ( mk ) }
        = t __el
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
