// inout_slice_given_a_new_value_runs_clean: an `inout [i` parameter given a literal, a call's slice, an owned local, a borrowed parameter (copied), on one path or in a loop: the caller's old buffer is released, the new one is the caller's
// main: the old buffer leaked, and `= p q` from a borrowed q left the caller sharing q's buffer (double free).
// map: §2.4 | A2 | runs-clean | - | agora #545: an inout slice given a fresh value, an owned local or a copy of a borrowed one releases the caller's old buffer once
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ setl inout [i p → v { = p [i | 3 4] }

@ setm inout [i p → v { = p ( mk ) }

@ setv inout [i p → v { : [i ys [i | 7 8 9] = p ys }

@ setq inout [i p [i q b c → v { ? c { = p q } {} }

@ main → i {
    : ~ [i d [i | 1 2]
    : [i q [i | 3 4 5]
    ( setl d )
    ( setm d )
    ( setv d )
    ( setq d q T )
    ( setq d q F )
    : ~ i k 0
    ~ < k 3 { ( setl d ) = k + k 1 }
    ( nurl_println_int + ( sum d ) ( sum q ) )
    ^ 0
}
