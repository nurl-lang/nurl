// owned_slice_moved_into_a_returned_literal_runs_clean: `: [i q ( mk )  ^ @ Box { q }`, `^ @ Holder { q 1 }`, nested `^ @ Outer { @ Box { q } 1 }`, on one path only, and a `: ~` q given a new value first: the literal takes the buffer, q releases nothing
// main: q was released at the return and the caller released the field again (heap-use-after-free).
// map: §7.6 | A2 | runs-clean | - | agora #545: an owned slice moved into a returned or nested literal hands its buffer to the field; the caller releases it once
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ boxit → Box { : [i q ( mk ) ^ @ Box { q } }

@ hold → Holder { : [i q ( mk ) ^ @ Holder { q 1 } }

@ nest → Outer { : [i q ( mk ) ^ @ Outer { @ Box { q } 1 } }

@ maybe b c → Box { : [i q ( mk ) ? c { ^ @ Box { q } } {} ^ @ Box { [i | 9] } }

@ regrown → Box { : ~ [i q ( mk ) = q [i | 4 5 6] ^ @ Box { q } }

@ main → i {
    : Box a ( boxit )
    : Holder h ( hold )
    : Outer o ( nest )
    : Box t ( maybe T )
    : Box f ( maybe F )
    : Box g ( regrown )
    ( nurl_println_int + + + + + ( sum . a v ) ( sum . h v ) ( sum . . o b v ) ( sum . t v ) ( sum . f v ) ( sum . g v ) )
    ^ 0
}
