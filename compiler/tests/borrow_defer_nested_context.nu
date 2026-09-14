// A `;` defer whose body double-frees, written in each context that
// only CONDITIONALLY arms the defer: a `?` arm, a `??` arm, a `~` body
// and a foreach body. The body is body-local and unconditional once the
// site runs, so every one of these is a definite double free — and all
// four compiled clean until the inverse fuzzer (FUZZ_GEN=reject) found
// them, because the exit-state replay only walked definitely-armed
// sites.
$ `stdlib/core/vec.nu`

: | Pick { PA i PB i }

@ main → i {
    ? T {
        ; {
            : ( Vec i ) a ( vec_new [i] )
            ( vec_free [i] a )
            ( vec_free [i] a )
        }
    } {}

    : Pick pick @ Pick { PA 1 }
    ?? pick {
        PA p → {
            ; {
                : ( Vec i ) b ( vec_new [i] )
                ( vec_free [i] b )
                ( vec_free [i] b )
            }
            p
        }
        PB p → p
    }

    : ~ i w 0
    ~ < w 1 {
        ; {
            : ( Vec i ) c ( vec_new [i] )
            ( vec_free [i] c )
            ( vec_free [i] c )
        }
        = w + w 1
    }

    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ~ x xs {
        ; {
            : ( Vec i ) d ( vec_new [i] )
            ( vec_free [i] d )
            ( vec_free [i] d )
        }
        ( nurl_println_int x )
    }
    ( vec_free [i] xs )
    ^ 0
}
