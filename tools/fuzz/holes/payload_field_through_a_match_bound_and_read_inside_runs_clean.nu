// payload_field_through_a_match_bound_and_read_inside_runs_clean: AGORA-941 guard — a `:` `??` join reading a field of the payload, used only while `g` lives: accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-941 guard: a bound `??` join over a payload field read inside its block
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
        ( nurl_println_int ( string_len __el ) )
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
