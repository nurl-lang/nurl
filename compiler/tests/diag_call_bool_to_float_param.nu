// diag_call_bool_to_float_param.nu — a bool rides the integer
// family (width 1), so handing it to a float parameter is the same
// never-legal float↔integer clash, previously emitted as
// `call double @half(i1 …)` and silently misread by the callee.
@ half f x → f { ^ x }

@ main → i {
    : b y T
    : f z ( half y )
    ^ 0
}
