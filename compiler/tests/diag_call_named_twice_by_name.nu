// diag_call_named_twice_by_name.nu — a keyword call that reorders its
// arguments and names one of them twice (`a:` before and after `c:`). The
// keyword path kept the later value in silence; it refuses the call and
// names the argument (agora #434).
@ f i a i b = 20 i c → i { ^ + + a b c }

@ main → i {
    : i r ( f c : 3 a : 1 a : 2 )
    ^ r
}
