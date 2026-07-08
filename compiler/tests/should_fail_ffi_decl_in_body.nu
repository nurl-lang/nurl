// An '&' FFI library import is a top-level declaration. Written inside a
// function body it used to be parsed as boolean/bitwise AND with a string
// left operand, dying with the misleading "operator & requires matching
// types — got s and unknown". The compiler now names the real mistake
// (top-level form in a body) — this lock only asserts the rejection.
// (Found via the genacc generation corpus: sonnet's histogram.nu declared
// malloc inside main in 4/5 samples.)
@ main → i {
    & `c` @ malloc i sz → *u
    : *u p ( malloc 80 )
    ( free p )
    ^ 0
}
