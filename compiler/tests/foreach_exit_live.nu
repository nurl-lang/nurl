// foreach_exit_live.nu — a foreach's exit path is LIVE, whatever its
// body did.
//
// gen_loop says so at its own exit label: "a loop that CAN exit resets
// did_ret: its exit path is live even when the body returned
// somewhere". A foreach always can — the check block branches to the
// exit the moment the index reaches the length — and it did not reset
// the flag. So a foreach whose body ends in `break` left `g_did_ret`
// set, and the ENCLOSING loop believed its own body had terminated and
// emitted its exit label with no branch before it.
//
// Two labels back to back is an EMPTY basic block, which LLVM rejects:
// `expected instruction opcode`, pointing at the second label, in
// generated IR with no source location. It takes a foreach that is the
// LAST statement of the enclosing loop's body AND whose own last
// statement is a `break` or `continue` — no conditional around it,
// because a `?` join resets the flag and hides it. Nothing in the tree
// was written that way; deleting the `?` from `? > x 2 { break } {}` in
// foreach_break_continue.nu was, and the shape below is the legal
// spelling of what that deletion produced.
//
// Same rule, the other loop. The answer is arithmetic: the foreach adds
// the first element of xs and breaks, three outer passes, 1+1+1 = 3.

@ main → i {
    : [i xs [i | 1 2 3]
    : ~ i s3 0
    : ~ i a 0
    ~ < a 3 {
        = a + a 1
        ~ x xs { = s3 + s3 x break }
    }
    ( nurl_print `s3=` ) ( nurl_print ( nurl_str_int s3 ) ) ( nurl_print `\n` )
    ^ ? == s3 3 0 1
}
