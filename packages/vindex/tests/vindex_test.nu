// vindex_test.nu — index gates: cosine/L2 top-1 matches the analytic
// nearest neighbour, IVF-flat recall@k against the exact index on a fixed
// clustered corpus, and a .vix save/load round-trips to identical results.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/vindex_test.nu /tmp/vt && /tmp/vt

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `src/vindex.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ gi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → x F → 0 } }

@ gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

// n vectors in `nc` gaussian-ish clusters of dim d (cluster centre + noise).
@ mkcorpus i n i d i nc i seed ( Vec f ) out → v {
    : Rng g ( rng_seed seed )
    // cluster centres
    : ( Vec f ) ctr ( vec_new [f] )
    : ~ i k 0
    ~ < k * nc d { ( vec_push [f] ctr * 10.0 - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
    : ~ i i2 0
    ~ < i2 n {
        : i cl % i2 nc
        : ~ i c 0
        ~ < c d {
            ( vec_push [f] out + ( gf ctr + * cl d c ) * 0.6 - * 2.0 ( rng_u01 g ) 1.0 )
            = c + c 1
        }
        = i2 + i2 1
    }
    ( vec_free [f] ctr )
    ( rng_free g )
}

// copy row `id` of `data` (dim d) into a fresh query vector
@ row ( Vec f ) data i id i d → ( Vec f ) {
    : ( Vec f ) q ( vec_new [f] )
    : ~ i c 0
    ~ < c d { ( vec_push [f] q ( gf data + * id d c ) ) = c + c 1 }
    ^ q
}

// how many of `got` (ids) appear in `want` (ids) — recall numerator
@ overlap ( Vec i ) got ( Vec i ) want → i {
    : ~ i hits 0
    : ~ i a 0
    ~ < a ( vec_len [i] got ) {
        : i gid ( gi got a )
        : ~ i b 0
        ~ < b ( vec_len [i] want ) { ? == ( gi want b ) gid { = hits + hits 1 } {} = b + b 1 }
        = a + a 1
    }
    ^ hits
}

@ main → i {
    : i N 400
    : i D 8
    : i NC 10
    : ( Vec f ) data ( vec_new [f] )
    ( mkcorpus N D NC 7 data )
    // a second copy for the IVF index (each index owns its data)
    : ( Vec f ) data2 ( vec_new [f] )
    : ~ i k 0
    ~ < k * N D { ( vec_push [f] data2 ( gf data k ) ) = k + k 1 }

    // ── cosine top-1 is the query's own row (distance 0) ──
    : *VIndex ex ( vx_build_exact data N D VX_COSINE )
    ( check == ( vx_n ex ) N `exact index holds N vectors` )
    : ( Vec i ) ids ( vec_new [i] )
    : ( Vec f ) ds ( vec_new [f] )
    : ~ b self_ok T
    : ~ i probe 0
    ~ < probe 20 {
        : i qid * probe 17
        : ( Vec f ) q ( row data qid D )
        : i got ( vx_search ex q 5 0 ids ds )
        ? & > got 0 == ( gi ids 0 ) qid {} { = self_ok F }
        ( vec_free [f] q )
        = probe + probe 1
    }
    ( check self_ok `cosine top-1 of a corpus vector is itself` )

    // ── L2 top-1 likewise ──
    : *VIndex exl ( vx_build_exact data2 N D VX_L2 )
    : ( Vec f ) q0 ( row data 3 D )
    : i g0 ( vx_search exl q0 3 0 ids ds )
    ( check & > g0 0 == ( gi ids 0 ) 3 `L2 top-1 of a corpus vector is itself` )
    // and its distance is (near) zero
    ( check < ( gf ds 0 ) 0.000001 `L2 self-distance is ~0` )
    ( vec_free [f] q0 )
    ( vx_free exl )

    // ── IVF recall@10 vs exact ──
    // fresh data copies (exact `ex` owns `data`; build ivf on a copy)
    : ( Vec f ) data3 ( vec_new [f] )
    = k 0
    ~ < k * N D { ( vec_push [f] data3 ( gf data k ) ) = k + k 1 }
    : *VIndex ivf ( vx_build_ivf data3 N D VX_COSINE NC 12 7 )
    ( check == ( vx_nlist ivf ) NC `IVF built NC clusters` )
    : ( Vec i ) eids ( vec_new [i] )
    : ( Vec f ) eds ( vec_new [f] )
    : ( Vec i ) iids ( vec_new [i] )
    : ( Vec f ) idsv ( vec_new [f] )
    : ~ i tot 0
    : ~ i hit 0
    : ~ i qp 0
    ~ < qp 40 {
        : i qid * qp 9
        : ( Vec f ) q ( row data qid D )
        : i ge ( vx_search ex q 10 0 eids eds )
        : i gi2 ( vx_search ivf q 10 4 iids idsv )
        = tot + tot ge
        = hit + hit ( overlap iids eids )
        ( vec_free [f] q )
        = qp + qp 1
    }
    : f recall / # f hit # f tot
    ( nurl_print `  IVF recall@10 (nprobe=4/` ) ( nurl_print_int NC )
    ( nurl_print `): ` ) ( nurl_print ( nurl_str_float recall ) ) ( nurl_print `\n` )
    ( check > recall 0.9 `IVF recall@10 > 0.9 vs exact` )

    // ── .vix save/load → identical IVF results ──
    : ( Vec u ) blob ( vx_save ivf )
    ?? ( vx_load blob ) {
        T lo → {
            ( check & & == ( vx_n lo ) N == ( vx_dim lo ) D == ( vx_nlist lo ) NC `.vix header round-trips` )
            : ( Vec i ) lids ( vec_new [i] )
            : ( Vec f ) ldsv ( vec_new [f] )
            : ( Vec f ) q ( row data 11 D )
            : i _a ( vx_search ivf q 10 4 iids idsv )
            : i _b ( vx_search lo q 10 4 lids ldsv )
            : ~ b same == ( vec_len [i] iids ) ( vec_len [i] lids )
            : ~ i z 0
            ~ & < z ( vec_len [i] iids ) same {
                ? == ( gi iids z ) ( gi lids z ) {} { = same F }
                = z + z 1
            }
            ( check same `loaded index returns identical search results` )
            ( vec_free [f] q ) ( vec_free [i] lids ) ( vec_free [f] ldsv )
            ( vx_free lo )
        }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) = g_fail + g_fail 1 }
    }
    ( vec_free [u] blob )

    ( vec_free [i] ids ) ( vec_free [f] ds )
    ( vec_free [i] eids ) ( vec_free [f] eds ) ( vec_free [i] iids ) ( vec_free [f] idsv )
    ( vx_free ex ) ( vx_free ivf )
    ( nurl_print `vindex_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
