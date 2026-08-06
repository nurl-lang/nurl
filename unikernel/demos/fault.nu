// unikernel/demos/fault.nu — the machine, asked to describe its own
// worst day.
//
// A guest with no IDT answers every CPU exception identically: it
// cannot deliver the fault, cannot deliver the double fault either,
// and shuts down. From the host that is indistinguishable from a clean
// exit — the hypervisor quits and the exit sentinel is simply missing —
// so the first thing anyone learns about a null dereference is that the
// output stopped. This demo makes two of them happen on purpose so the
// gate can read what the machine says about them.
//
//   args="null 0"       a store through address 0        → #PF at 0
//   args="stack 100000000"  a recursion deeper than the boot stack
//                       → #PF on its guard page, delivered on the IST
//                       stack, because the ordinary one is exactly
//                       what ran out
//
// BOTH ADDRESSES COME FROM THE COMMAND LINE, and that is not decoration.
// A store through a literal null and a provably infinite recursion are
// both undefined behaviour, and LLVM answers undefined behaviour by
// deleting the code around it: the first version of this demo, written
// with a literal 0 and an unbounded recursion, HUNG instead of faulting
// on Linux and in the guest alike. A number that arrives at run time is
// a number the optimiser cannot reason about, so the machine is the one
// that decides what happens — which is the only thing being tested here.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: NullTarget { i word }

@ __touch i addr → i {
    : *NullTarget p # *NullTarget addr
    = . p word 1
    ^ . p word
}

// Each frame keeps a heap handle across the call and does work after
// it, so this is neither a tail call nor a pure function the optimiser
// may fold away. `n` counts down from a number given on the command
// line: the recursion terminates in principle and exhausts the stack in
// practice, which is the combination that survives -O2.
@ __deep i n → i {
    : ( Vec i ) pad ( vec_with_cap [i] 2 )
    ( vec_push [i] pad n )
    : i deeper ? > n 0 ( __deep - n 1 ) 0
    : i mine ?? ( vec_get [i] pad 0 ) { T x → x F → 0 }
    ( vec_free [i] pad )
    ^ + deeper mine
}

@ main → i {
    : s mode ? > ( nurl_argc ) 1 ( nurl_argv 1 ) `null`
    : i arg ? > ( nurl_argc ) 2 ( nurl_str_to_int ( nurl_argv 2 ) ) 0
    ( nurl_print `about to fault: ` )
    ( nurl_print mode )
    ( nurl_print `\n` )
    ( flush )
    ? != ( nurl_str_eq mode `stack` ) 0 {
        ( nurl_print ( nurl_str_int ( __deep arg ) ) )
    } {
        ( nurl_print ( nurl_str_int ( __touch arg ) ) )
    }
    ( nurl_print `still here — nothing faulted\n` )
    ^ 0
}
