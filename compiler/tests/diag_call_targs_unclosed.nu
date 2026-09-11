// diag_call_targs_unclosed.nu — a call's generic type-argument list
// whose ']' is missing. The walk that collects the type arguments ended
// only on ']', so at end of input it spun on TT_EOF forever and
// `nurlc file.nu` HUNG — the same shape the unclosed generic struct body
// once had, and the reason that test exists. EOF now ends the walk and
// the expect below reports it.
//
// Found by deleting one token at a time from every program in the corpus
// and requiring the compiler to answer: reject the file, or emit the
// main it still declares.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i )
    ^ 0
}
