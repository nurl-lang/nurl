// diag_call_kwargs_float_arg.nu — the named-argument call path
// reorders arguments into declaration order and used to bypass EVERY
// per-argument check while doing it: `( scale x: y k: 2 )` slid a float
// into the 'i' parameter unflagged. The kwargs path must run the same
// argument law as the positional path.
@ scale i x i k → i { ^ * x k }

@ main → i {
    : f y 1.5
    ^ ( scale x : y k : 2 )
}
