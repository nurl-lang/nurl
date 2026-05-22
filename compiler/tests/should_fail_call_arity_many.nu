// should_fail_call_arity_many.nu — a call supplying MORE arguments
// than the callee declares. The mirror of should_fail_call_arity_few:
// gen_call checks the parsed argument count against the parameter
// count scan_fn_sigs recorded for this non-generic @-function and
// rejects the surplus. Expect COMPILE FAIL.

@ add i x i y → i { ^ + x y }

@ main → i {
    : i r ( add 3 4 5 )
    ^ r
}
