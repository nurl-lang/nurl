// inout_holder_repointed_by_a_shadowing_local_of_its_name: `: ~ W w …` inside
// the helper shadows its inout `w`; `= w @ W { `fresh` }` writes only the
// local. Matched by name, the parameter was credited (formal's review of
// #1709). The write must be to the parameter's own slot: still refused.
// map: §3.3d | A2 | rejected | - | a helper that gives a literal to a local shadowing its inout holder's name: not the parameter, not credited (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { : ~ W w @ W { `a` } = w @ W { `fresh` } ^ 0 }

@ main → i { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) : ~ W w @ W { ( string_data b ) } ( reset w ) ( string_free b ) ( nurl_println . w v ) ^ 0 }
