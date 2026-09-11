// diag_match_no_arms.nu — a '??' with an empty arm block. Nothing is
// dispatched, and the merge label the match emits afterwards then has no
// predecessor: a label immediately after a non-terminator instruction,
// which is invalid IR. Only clang reported it — "expected instruction
// opcode" at a line number in generated text, with no NURL source
// location. An enum scrutinee never got this far (the non-exhaustive
// check catches it first), and neither did an option or a result; an
// integer or string one did.

@ main → i {
    : ~ i k 0
    ?? k {}
    ( nurl_print `unreachable\n` )
    ^ 0
}
