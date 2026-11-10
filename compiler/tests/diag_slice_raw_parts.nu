// diag_slice_raw_parts.nu — a slice built from a pointer and a length
// takes the buffer behind the pointer for its own and frees it. Over
// another slice's buffer that is two owners of one block (freed twice, or
// read after the first one freed it — this program returned freed memory
// before the rule), so safe code may not write it: an `unsafe` function
// vouches for the buffer (agora #545).
@ firsts [i a → [i {
    ^ @ [i { . a 0 2 }
}

@ main → i {
    : [i a [i | 1 2 3]
    : [i f ( firsts a )
    : ~ i t 0
    ~ x f { = t + t x }
    ^ t
}
