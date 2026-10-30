// diag_struct_lit_result_into_option.nu — a result value in a struct
// literal's option field (agora #129): two anonymous aggregates of
// different shapes, invalid IR only clang used to reject.
: P { ? i o }

@ main → i {
    : !i s r @ !i s { T 7 }
    : P p @ P { r }
    ^ 0
}
