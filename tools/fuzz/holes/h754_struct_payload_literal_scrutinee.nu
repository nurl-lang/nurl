// H754: agora #182 — the same with a boxed struct payload, as a statement (struct_payload_literal_scrutinee).
// Closed: a `??` over an enum literal gives the literal an owner of its own, as a call's result has: dropped at the scope's end, its payload taken out by an arm that hands it on (gen_match `__m_tmp_slot__`; agora #182).
// v0.80.0 and main: accepted; LeakSanitizer.
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

@ main → i {
    ?? @ G { V @ P { ( mk ) 1 } } { V p → { ( nurl_println_int . p n ) } Nil → {} }
    ^ 0
}
