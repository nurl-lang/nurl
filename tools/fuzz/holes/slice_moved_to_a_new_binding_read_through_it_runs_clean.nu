// slice_moved_to_a_new_binding_read_through_it_runs_clean: `: [i c a` out of an owned slice, then c read, in a loop and handed back: c owns the buffer, released once
// Guard for the walk's move of `: [i c a`: reads through the new name, and a given a new value after it, stay accepted.
// map: §2.1 | A2 | runs-clean | - | agora #664: an owned slice moved to a new binding is read and handed back through it; the old name given a fresh slice is its own again
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2 3] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

@ pass → [i {
    : ~ [i a ( mk )
    : [i c a
    = a [i | 9]
    ( nurl_println_int + ( sum c ) ( sum a ) )
    ^ c
}

@ main → i {
    : ~ i k 0
    ~ < k 3 { : [i r ( pass ) ( nurl_println_int ( sum r ) ) = k + k 1 }
    ^ 0
}
