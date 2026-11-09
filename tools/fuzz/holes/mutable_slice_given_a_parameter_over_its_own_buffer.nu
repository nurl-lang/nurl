// mutable_slice_given_a_parameter_over_its_own_buffer: a mutable slice binding that owns its buffer (`: ~ [i d [i | 1 2 3]`) given a slice parameter (`= d p`) stayed on the owned list, so its drop freed the caller's buffer, which the caller then read.
// Closed: a mutable owned slice has an owner flag (agora #540); `= d p` frees d's old buffer (p does not point into it) and clears the flag, so d's drop frees nothing. `= d ( keep d )` over the same buffer keeps it owned.
// main ad960922: AddressSanitizer: heap-use-after-free in main reading `a` after `( use a )`.
// map: §7.6 | A2 | runs-clean | - | agora #540: a mutable owned slice given a parameter freed the caller's buffer at its drop
@ keep [i p → [i { ^ p }

@ use [i p → i {
    : ~ [i d [i | 1 2 3]
    = d p
    ~ x d { ( nurl_println ( nurl_str_int x ) ) }
    : ~ [i e [i | 4]
    = e ( keep e )
    ~ x e { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

@ main → i {
    : [i a [i | 5 6]
    ( use a )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
