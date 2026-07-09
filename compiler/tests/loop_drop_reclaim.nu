// loop_drop_reclaim.nu — a `% Drop` value bound inside a loop body must be
// dropped at the END OF EACH ITERATION (its hoisted alloca is reused next
// iteration, so the previous value's owned resources would otherwise leak).
// This is the normal-path root cause behind the recover_unwind CI leak: the
// while-loop scope exit freed owned strings/vecs but skipped user `% Drop`
// destructors. Run under LSAN_DETECT_LEAKS=1 it must be leak-clean.

: Handle { * u buf }

% Drop ( Handle ) { @ drop Handle h → v { ( nurl_free # s . h buf ) } }

@ main → i {
    : ~ i k 0
    ~ < k 100 {
        : Handle h @ Handle { # *u ( malloc 32 ) }
        = k + k 1
    }
    ( nurl_print `dropped 100\n` )
    ^ 0
}
