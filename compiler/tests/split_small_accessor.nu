// A small accessor called from several parts of a split build (Agora #527).
//
// Under `--split` each part goes through ThinLTO on its own. A function a
// part imports cannot be inlined there (the IR mover remaps its struct
// types, and LLVM never inlines a call whose type differs from its
// callee's), so the splitter gives every part that calls a small function
// a copy of its own. `vec_get` and `vec_put` on an `f` vector are the
// accessors a codec's inner loops are made of (`__at` is the codec's own
// zero-default read); split_equivalence.sh checks
// that every part calling one defines it, and that this program prints
// the same split as whole.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

// A read that is 0 out of range, as the codec reads its coefficients.
@ __at ( Vec f ) v i p → f {
    ?? ( vec_get [f] v p ) { T x → { ^ x } F _ → { ^ 0.0 } }
}

@ __fill i n → ( Vec f ) {
    : ~ ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v + 0.5 # f k ) = k + k 1 }
    ^ v
}

// An 8-point butterfly over each row, the shape of an IDCT pass.
@ __rows ( Vec f ) v i n → f {
    : ~ f acc 0.0
    : ~ i r 0
    ~ < + r 8 n {
        : f a ( __at v r )
        : f b ( __at v + r 7 )
        : f c ( __at v + r 3 )
        : f d ( __at v + r 4 )
        = acc + acc - * + a b 0.5 * - c d 0.25
        = r + r 8
    }
    ^ acc
}

// The same over columns, stride 8.
@ __cols ( Vec f ) v i n → f {
    : ~ f acc 0.0
    : ~ i c 0
    ~ < + c 56 n {
        : f a ( __at v c )
        : f b ( __at v + c 56 )
        = acc + acc * - a b 0.125
        = c + c 1
    }
    ^ acc
}

// Scale in place: a reader and a writer in one loop.
@ __scale ( Vec f ) v i n f k → v {
    : ~ i i 0
    ~ < i n { ( vec_put [f] v i * k ( __at v i ) ) = i + i 1 }
}

@ main → i {
    : ~ ( Vec f ) v ( __fill 512 )
    : f r ( __rows v 512 )
    ( __scale v 512 2.0 )
    : f c ( __cols v 512 )
    ( puts ( float_to_string r ) )
    ( puts ( float_to_string c ) )
    ^ 0
}
