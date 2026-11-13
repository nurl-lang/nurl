// slice_field_of_a_parameter_handed_back_is_lent_runs_clean: `@ fld Holder p → [i { ^ . p v }`, and `@ cur [i p → [i { : ~ [i r p  ^ r }`: what they hand back is the caller's argument's, lent, and the caller releases it once
// A slice return publishes whether it hands over the function's own; a parameter's field, or a cursor over a parameter, is not (it was answered owned, and the caller freed its argument's buffer twice).
// map: §7.6 | A2 | runs-clean | - | agora #540: a slice field of a parameter, or a `: ~` cursor over a parameter, handed back is lent; the caller's own release frees it once
$ `stdlib/core/vec.nu`

@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }

: Holder { [i v i n }

@ fld Holder p → [i { ^ . p v }

@ cur [i p → [i { : ~ [i r p ^ r }

@ main → i {
    : Holder h @ Holder { [i | 1 2] 3 }
    : [i ys ( fld h )
    : [i a [i | 4 5]
    : [i x ( cur a )
    ( nurl_println_int + + + ( sum ys ) ( sum . h v ) ( sum x ) ( sum a ) )
    ^ 0
}
