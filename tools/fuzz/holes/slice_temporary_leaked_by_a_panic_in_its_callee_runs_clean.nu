// slice_temporary_leaked_by_a_panic_in_its_callee_runs_clean: `( boom ( mk ) k )`, boom panics under recover
// Closed (agora #891): a slice temporary is the caller's while its callee runs: its slot is journaled for the call (__slice_jthunk_of), as a handle temporary's is, so a panic in the callee releases it.
// main 2a7b1153: LeakSanitizer reported each panicking call's slice.
// map: §7.2 | A2 | runs-clean | - | AGORA-891: `( boom ( mk ) k )`, boom panics under recover
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ boom [i a i k → i { ? > k 2 { ( panic `too big` ) } {} ^ . a 1 }
@ main → i {
    : ~ i caught 0
    : ~ i k 0
    ~ < k 5 {
        : !v PanicInfo r ( recover \ → v { : i _n ( boom ( mk ) k ) } )
        ?? r { T _ → {} F p → { = caught + caught 1 ( panic_info_free p ) } }
        = k + k 1
    }
    ( nurl_println_int caught )
    ^ 0
}
