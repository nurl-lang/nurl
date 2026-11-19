// fresh_slice_handed_to_a_pick_and_discarded_runs_clean: `( pick T ( mk ) a )` and `( pick F ( mk ) a )` as statements and as then-only arms, `pick` handing back one of its two slice parameters
// Closed (agora #903): the call copies what it hands back of its temporary on the runs it lent it (mem_own_lendback), and a discarded result is released by that copy's bit (__call_copied_own) where the statement or the arm ends; the temporary itself goes after the call.
// main 85a31ca: LeakSanitizer: the copy of the fresh slice leaked.
// map: §7.6 | A2 | runs-clean | - | agora #903: a fresh slice handed to a callee that may hand it back, the result discarded as a statement or a then-only arm
@ mk → [i { ^ [i | 1 2 3] }
@ pick b c [i x [i y → [i { ? c { ^ x } {} ^ y }

@ main → i {
    : [i a [i | 4 5]
    : i c 1
    ( pick T ( mk ) a )
    ( pick F ( mk ) a )
    ? > c 0 { ( pick T ( mk ) a ) } {}
    ? > c 0 { ( pick F ( mk ) a ) } {}
    ~ x a { ( nurl_println_int x ) }
    ^ 0
}
