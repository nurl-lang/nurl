// slice_field_taken_out_of_a_temporary_returned_runs_clean: `@ rs → [i { ^ . ( mkb ) s }` (defined before and after its caller) and `@ rp b c Bag d → [i { ^ . ( mkp c d ) s }` (its temporary fresh on one run, a lent parameter on the other), each handed to a call and bound
// Closed (agora #936): a slice the read takes out of a temporary (h266, agora #895) and returns answers by the read's flag, as a String does: no fresh-slice veto and no borrow veto, and its callers ask the function's module-end constant for it (`rettf##`, __slice_call_run_bit; `@.__nurl_retslc` for one compiled after its caller).
// main 08e56f54: AddressSanitizer: heap-use-after-free (h232 released the struct under the slice it handed back, agora #895); with github#2108's take-out, LeakSanitizer: the slices handed back leaked, taken for a lend.
// map: §7.6 | A2 | runs-clean | - | agora #936: a slice field taken out of a temporary and returned, the callee before and after its caller, and one whose temporary is fresh or lent per run
: Bag { [i s i n }

@ mk → [i { ^ [i | 1 2 3] }
@ mkb → Bag { ^ @ Bag { ( mk ) 3 } }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }
@ rs → [i { ^ . ( mkb ) s }
@ mkp b c Bag d → Bag { ? c { ^ @ Bag { ( mk ) 1 } } {} ^ d }
@ rp b c Bag d → [i { ^ . ( mkp c d ) s }

@ main → i {
    ( nurl_println_int ( ln ( rs ) ) )
    : [i y ( rs )
    ( nurl_println_int ( ln y ) )
    ( nurl_println_int ( ln ( ra ) ) )
    : [i z ( ra )
    ( nurl_println_int ( ln z ) )
    : Bag d @ Bag { [i | 5 6] 2 }
    ( nurl_println_int ( ln ( rp T d ) ) )
    ( nurl_println_int ( ln ( rp F d ) ) )
    : [i u ( rp T d )
    : [i v ( rp F d )
    ( nurl_println_int + ( ln u ) ( ln v ) )
    ( nurl_println_int ( ln . d s ) )
    ^ 0
}

@ ra → [i { ^ . ( mkb ) s }
