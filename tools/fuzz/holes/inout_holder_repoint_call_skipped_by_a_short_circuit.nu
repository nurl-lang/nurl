// inout_holder_repoint_call_skipped_by_a_short_circuit: `: b r & F ( reset w )`
// never calls reset, yet the caller took w as repointed (formal's review of
// #1709). No credit applies inside a right operand of `&` / `|`: still
// refused.
// map: §3.3d | A2 | rejected | - | a repointing helper called as the right operand of `&`, which may skip it: no credit at that call (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → b { = w @ W { `fresh` } ^ T }

@ main → i { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) : ~ W w @ W { ( string_data b ) } : b r & F ( reset w ) ( string_free b ) ( nurl_println . w v ) ^ 0 }
