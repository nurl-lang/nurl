// mac_row_agree.nu — nurl_mac_row (docs/spec.md, wide arithmetic)
// against the plain nurl_mac chain it replaces. On a CPU with BMI2 and
// ADX the row runs the two-carry-chain asm (mulx, adcx, adox);
// crypto_tier_ir.sh runs this again with NURL_CPU_ADX=0, and on any
// other CPU or target the row is the portable loop — one output for
// all of them.
//
// Every width from 0 to 40 limbs, so every split of a row into single
// limbs, the block of four and blocks of eight; operands pseudorandom
// from a fixed seed, with all-ones rows, multipliers and accumulators
// mixed in (the widest carries both chains can see). Each result and
// carry is folded into a checksum, so one wrong word anywhere changes
// the last line.

$ `stdlib/core/vec.nu`

: ~ u64 g_rng 0x9e3779b97f4a7c15

@ rnd → u64 {
    = g_rng ^^ g_rng << g_rng 13
    = g_rng ^^ g_rng >> g_rng 7
    = g_rng ^^ g_rng << g_rng 17
    ^ g_rng
}

// A limb for trial t: all ones on every third trial (kind 1), else
// pseudorandom.
@ limb i kind → u64 { ^ ? == kind 1 # u64 - 0 1 ( rnd ) }

// rp[0..n) += ap[0..n)·b by the nurl_mac chain, one carry at a time.
unsafe @ ref_row * i rp * i ap i n u64 b → u64 {
    : ~ u64 c 0
    : ~ i j 0
    ~ < j n {
        : u64 a # u64 . ap j
        : u64 t # u64 . rp j
        : u64 lo ( nurl_mac_lo a b t c )
        = c ( nurl_mac_hi a b t c )
        = . rp j # i lo
        = j + j 1
    }
    ^ c
}

unsafe @ main → i {
    : ~ i bad 0
    : ~ i rows 0
    : ~ u64 sum 0
    : ~ i n 0
    ~ <= n 40 {
        : ~ i t 0
        ~ < t 12 {
            : ( Vec i ) a ( vec_zeroed [i] + n 1 )
            : ( Vec i ) r1 ( vec_zeroed [i] + n 1 )
            : ( Vec i ) r2 ( vec_zeroed [i] + n 1 )
            : *i ap ( vec_data [i] a )
            : *i p1 ( vec_data [i] r1 )
            : *i p2 ( vec_data [i] r2 )
            : i ka % t 3
            : i kr % / t 3 3
            : ~ i j 0
            ~ < j n {
                = . ap j # i ( limb ka )
                : u64 x ( limb kr )
                = . p1 j # i x
                = . p2 j # i x
                = j + j 1
            }
            // the word past the row: the primitive must not touch it
            = . p1 n # i 0x5a5a5a5a5a5a5a5a
            = . p2 n # i 0x5a5a5a5a5a5a5a5a
            : u64 b ? == % t 4 3 # u64 - 0 1 ( rnd )
            : u64 c1 ( nurl_mac_row p1 ap n b )
            : u64 c2 ( ref_row p2 ap n b )
            : ~ i same ? == c1 c2 1 0
            = j 0
            ~ <= j n {
                ? != . p1 j . p2 j { = same 0 } {}
                = sum + * sum 0x100000001b3 # u64 . p1 j
                = j + j 1
            }
            = sum + * sum 0x100000001b3 c1
            ? == same 1 {} {
                ( nurl_print `MISMATCH n=` ) ( nurl_print_int n )
                ( nurl_print ` trial=` ) ( nurl_print_int t ) ( nurl_print `\n` )
                = bad + bad 1
            }
            = rows + rows 1
            = t + t 1
        }
        = n + n 1
    }
    // A literal width, as the RSA kernels call it.
    : ( Vec i ) a ( vec_zeroed [i] 16 )
    : ( Vec i ) r ( vec_zeroed [i] 16 )
    : *i ap ( vec_data [i] a )
    : *i rp ( vec_data [i] r )
    : ~ i j 0
    ~ < j 16 { = . ap j # i - 0 1 = . rp j # i - 0 1 = j + j 1 }
    : u64 c ( nurl_mac_row rp ap 16 # u64 - 0 1 )
    // All ones everywhere: (2^1024 − 1)·2^64 = 2^1088 − 2^64, the
    // largest a 16-limb row can produce; checked against the chain.
    : ( Vec i ) r2 ( vec_zeroed [i] 16 )
    : *i p2 ( vec_data [i] r2 )
    = j 0
    ~ < j 16 { = . p2 j # i - 0 1 = j + j 1 }
    : u64 c2 ( ref_row p2 ap 16 # u64 - 0 1 )
    : ~ i lit ? == c c2 1 0
    = j 0
    ~ < j 16 { ? != . rp j . p2 j { = lit 0 } {} = j + j 1 }
    ? == lit 1 {} { ( nurl_print `MISMATCH literal width 16\n` ) = bad + bad 1 }
    ( nurl_print `rows: ` ) ( nurl_print_int rows ) ( nurl_print `, mismatches: ` ) ( nurl_print_int bad ) ( nurl_print `\n` )
    ( nurl_print `checksum: ` ) ( nurl_print_int # i sum ) ( nurl_print `\n` )
    ^ ? == bad 0 0 1
}
