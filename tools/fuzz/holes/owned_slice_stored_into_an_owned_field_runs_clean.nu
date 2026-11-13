// owned_slice_stored_into_an_owned_field_runs_clean: `= . h v q` with q an owned slice, a parameter's slice (copied), a literal, a call, in a loop and on one path: the field takes or copies it, and the value it replaces is released
// main: q and the field both released the buffer (double free), or the replaced value leaked.
// map: §7.6 | A2 | runs-clean | - | agora #545: a slice stored into a field its binding owns moves an owned slice in, copies any other, and releases the one it replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ fill b c [i p → Holder {
    : ~ Holder h @ Holder { [i | 0] 1 }
    : [i q ( mk )
    ? c { = . h v q } { = . h v p }
    ^ h
}

@ main → i {
    : [i a [i | 4 5]
    : Holder x ( fill T a )
    : Holder y ( fill F a )
    : ~ Holder h @ Holder { [i | 0] 1 }
    = . h v [i | 6 7]
    = . h v ( mk )
    : ~ i k 0
    ~ < k 3 { : [i q ( mk ) = . h v q = k + k 1 }
    ( nurl_println_int + + + ( sum . x v ) ( sum . y v ) ( sum . h v ) ( sum a ) )
    ^ 0
}
