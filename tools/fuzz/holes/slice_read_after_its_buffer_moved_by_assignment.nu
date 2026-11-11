// slice_read_after_its_buffer_moved_by_assignment: an owned slice `a` assigned to another (`= t a`), `t` then given a new literal — which frees the buffer it took from `a` — and `a` read.
// Refused (agora #634): `= t a` moves the buffer, as `= b a` moves any owner (docs/MEMORY.md §2.2), and `a` is dead until it is given a new value. It compiled before — an owned slice's assignment was no move to the walk — and `a` was read after `= t [ … ]` freed its buffer (heap-use-after-free).
// map: §2.2 | A2 | rejected | - | agora #634: an owned slice read after an assignment moved its buffer to another, which was then given a new value
@ main → i {
    : ~ [i a [i | 1 2]
    : ~ [i t [i | 6]
    = t a
    = t [i | 7 8 9]
    : ~ i sum 0
    ~ x a { = sum + sum x }
    ~ y t { = sum + sum y }
    ( nurl_println_int sum )
    ^ 0
}
