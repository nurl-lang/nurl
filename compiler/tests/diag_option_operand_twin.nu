// diag_option_operand_twin.nu — an option reaching an arithmetic operator.
// The operands print as NURL types ('?i', not the lowered '{ i1, i64 }'),
// and since the option came from 'vec_get', whose non-option twin
// 'vec_at' exists, the diagnostic names that twin.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ^ + ( vec_get [i] v 0 ) ( vec_get [i] v 1 )
}
