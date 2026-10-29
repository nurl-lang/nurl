// block_tail_field_ok.nu — a value block whose tail reads a field of a
// struct the block binds itself (agora #180):
// - returned (`^ { : P q … . q s }`), directly or through a nested block:
//   handed back as `^ . q s` is, the field moved out of q;
// - as a `?` / `??` arm, returned or bound: the field moves out of the
//   arm's own struct, which is then dropped at the arm's exit — a struct
//   with a `% Drop` of its own keeps a copy for that drop.
// Runs clean under the sanitizers.

$ `stdlib/core/string.nu`

: P { String s i n }

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

: | G {
    V P
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ direct i n → String { ^ { : P q @ P { ( mk ) n } . q s } }

@ nested i n → String { ^ { : i k + n 1 { : P q @ P { ( mk ) k } . q s } } }

@ in_match G g → String { ^ ?? g { V p → { : P q @ P { ( mk ) . p n } . q s } Nil → ( mk ) } }

@ in_cond b c → String { ^ ? c { : P q @ P { ( mk ) 1 } . q s } ( mk ) }

@ with_drop b c → String { ^ ? c { : D q @ D { ( mk ) 7 } . q s } ( mk ) }

@ main → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        = acc + acc ( string_len ( direct k ) )
        = acc + acc ( string_len ( nested k ) )
        = acc + acc ( string_len ( in_match @ G { V @ P { ( mk ) k } } ) )
        = acc + acc ( string_len ( in_cond > k 4 ) )
        : G gk @ G { V @ P { ( mk ) k } }
        : String b ?? gk { V p → { : P q @ P { ( mk ) 2 } . q s } Nil → ( mk ) }
        = acc + acc ( string_len b )
        = k + k 1
    }
    ( nurl_println_int acc )
    ( nurl_println_int ( string_len ( with_drop T ) ) )
    ^ 0
}
