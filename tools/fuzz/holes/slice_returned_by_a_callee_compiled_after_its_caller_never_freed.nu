// slice_returned_by_a_callee_compiled_after_its_caller_never_freed: agora #510 — whether a call's slice result was the caller's to free was a flag the callee published when it was compiled, so a callee defined below its caller, or a generic instance, handed back a slice nobody freed.
// Closed: a slice result is owned by its type, whichever function made it and whenever that function is compiled; a call's answer says only whether the value was lent (mem_call_retown).
// main (before this PR): LeakSanitizer, both buffers.
// map: §7.6 | A2 | runs-clean | - | agora #510: a slice returned by a callee defined below its caller, or by a generic instance, was never freed (leak)
@ main → i {
    {
        : [i sl ( mk )
        ~ x sl { ( nurl_println ( nurl_str_int x ) ) }
    }
    : [i g ( mkg [i] 1 2 )
    ~ x g { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

@ mk → [i {
    : [i sl [i | 1 2 3]
    ^ sl
}

@ mkg [T] T a T b → [T {
    : [T sl [T | a b]
    ^ sl
}
