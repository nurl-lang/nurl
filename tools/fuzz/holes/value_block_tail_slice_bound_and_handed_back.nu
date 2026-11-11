// value_block_tail_slice_bound_and_handed_back: `: [i b { : [i u [i | 9 n] u }`, then `^ b` — with a defer that reads `b`, with a `^ u` inside the block, and with neither.
// Closed: a `:` binding of a value block whose tail is a slice the block bound takes the buffer over from that binding, as `= dst src` does (mem_own_slice_remove of the tail binding, mem_own_add of the new one). Both listed, the function released the block binding's buffer on the way out and handed the same buffer back through `b` (agora #653; the family is #664).
// main 2aae2fa: accepted; AddressSanitizer: heap-use-after-free in the caller.
// map: §7.1 | A2 | runs-clean | - | agora #653: a value block's tail slice bound with `:` and handed back — the block's binding released the buffer the caller was given
@ sum [i xs → i {
    : ~ i t 0
    ~ w xs { = t + t w }
    ^ t
}

@ plain i n → [i {
    : [i b { : [i u [i | 9 n] u }
    ^ b
}

@ kept i n → [i {
    : [i b { : [i u [i | 9 n] u }
    ; { ( nurl_println_int ( sum b ) ) }
    ^ b
}

@ inside i n → [i {
    : [i b { : [i u [i | 9 n] ? == n 4 { ^ u } {} u }
    ; { ( nurl_println_int ( sum b ) ) }
    ^ b
}

@ main → i {
    : [i a ( plain 1 )
    : [i c ( kept 2 )
    : [i d ( inside 3 )
    : [i e ( inside 4 )
    ( nurl_println_int + + + ( sum a ) ( sum c ) ( sum d ) ( sum e ) )
    ^ 0
}
