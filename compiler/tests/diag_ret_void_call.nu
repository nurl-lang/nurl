// diag_ret_void_call.nu — returning the result of a 'v' function.
//
// The hint used to read "likely a conditional with incompatible branch
// types" and nothing else, which is a guess — and the wrong one for the
// commonest way to reach this. Returning a void call is named first now.
@ nothing → v {}

@ main → i { ^ ( nothing ) }
