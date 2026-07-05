// tests/fuzz.nu — deterministic in-process fuzz of every decoder.
//   fuzz <seedfile>
// Three sweeps over the seed: every prefix (stepped on big seeds), point
// mutations at stepped offsets (0x00 / 0xFF / bit-flipped), and LCG random
// multi-byte mutations. Every mutant goes through image_decode (which
// routes to PNG / JPEG / PPM by magic); decoded images are freed. Run under
// AddressSanitizer + a timeout: any OOB, leak or hang fails the harness.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/image.nu`

: ~ i g_ok 0
: ~ i g_tot 0

@ try_bytes ( Vec u ) b → v {
    = g_tot + g_tot 1
    ?? ( image_decode b ) {
        T im → { ( image_free im ) = g_ok + g_ok 1 }
        F _ → {}
    }
}

@ copy_of ( Vec u ) src → ( Vec u ) {
    : ( Vec u ) d ( vec_new [u] )
    ( vec_extend [u] d src )
    ^ d
}

@ main → i {
    ? >= ( env_args_count ) 2 {} { ( nurl_eprintln `usage: fuzz <seedfile> [phase]` ) ^ 2 }
    : String a1 ( env_arg 1 )
    : ~ i phase 0
    ? >= ( env_args_count ) 3 {
        : String a2 ( env_arg 2 )
        = phase - ( string_get a2 0 ) 48
        ( string_free a2 )
    } {}
    : ~ i rc 0
    : !( Vec u ) IoErr r ( read_file_bytes ( string_data a1 ) )
    ?? r {
        T seed → {
            : i n ( vec_len [u] seed )

            ? || == phase 0 == phase 1 {
            // 1) truncation sweep — every prefix on small seeds
            : i step1 ? > n 3000 { / n 1500 } { 1 }
            : ~ i len 0
            ~ <= len n {
                : ( Vec u ) pre ( vec_new [u] )
                : ~ i k 0
                ~ < k len { ( vec_push [u] pre ( __b seed k ) ) = k + k 1 }
                ( try_bytes pre )
                ( vec_free [u] pre )
                = len + len step1
            }
            } {}

            ? || == phase 0 == phase 2 {
            // 2) point mutations at stepped offsets
            : i step2 ? > n 1200 { / n 1200 } { 1 }
            : ~ i off 0
            ~ < off n {
                : i orig ( __b seed off )
                : ~ i vi 0
                ~ < vi 3 {
                    : i v ? == vi 0 { 0 } { ? == vi 1 { 255 } { ^^ orig 128 } }
                    ? == v orig {} {
                        : ( Vec u ) mut ( copy_of seed )
                        ( vec_set [u] mut off v )
                        ( try_bytes mut )
                        ( vec_free [u] mut )
                    }
                    = vi + vi 1
                }
                = off + off step2
            }
            } {}

            ? || == phase 0 == phase 3 {
            // 3) LCG random multi-byte mutations (fixed seed → reproducible)
            : ~ i x 305419896
            : ~ i round 0
            ~ < round 400 {
                : ( Vec u ) mut ( copy_of seed )
                = x + * x 6364136223846793005 1442695040888963407
                : ~ i nm + 1 % # i & >> x 33 65535 9
                : ~ i m 0
                ~ & < m nm > n 0 {
                    = x + * x 6364136223846793005 1442695040888963407
                    : i o % # i & >> x 33 1073741823 n
                    = x + * x 6364136223846793005 1442695040888963407
                    ( vec_set [u] mut o % # i & >> x 33 1023 256 )
                    = m + m 1
                }
                ( try_bytes mut )
                ( vec_free [u] mut )
                = round + round 1
            }
            } {}

            ( vec_free [u] seed )
            : String msg ( string_from `fuzz done: ` )
            ( string_push_int msg g_tot )
            ( string_push_str msg ` mutants, ` )
            ( string_push_int msg g_ok )
            ( string_push_str msg ` still decoded` )
            ( puts ( string_data msg ) )
            ( string_free msg )
        }
        F _ → { ( nurl_eprintln `cannot read seed` ) = rc 2 }
    }
    ( string_free a1 )
    ^ rc
}
