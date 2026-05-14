// Test: stdlib/std/hashmap.nu — map_iter walks (key, value) pairs.

$ `stdlib/std/hashmap.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`

@ main → i {
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }

    // ── Build a HashMap[s i] ──
    : ( HashMap s i ) m ( map_new [s i] )
    ( map_set [s i] m `alpha` 1 hs es )
    ( map_set [s i] m `bravo` 2 hs es )
    ( map_set [s i] m `charlie` 3 hs es )
    ( map_set [s i] m `delta` 4 hs es )

    // ── Walk via map_iter, accumulate sum manually ──
    : ( @ ?( Pair s i ) i ) it ( map_iter [s i] m )
    : ~ i sum 0
    : ~ i cnt 0
    : ~ b done F
    ~ ! done {
        : ?( Pair s i ) g ( it 0 )
        ?? g {
            T p → {
                = sum + sum ( pair_second [s i] p )
                = cnt + cnt 1
            }
            F → { = done T }
        }
    }
    ( it 1 )
    ( nurl_print `sum=` ) ( nurl_print ( nurl_str_int sum ) ) ( nurl_print `\n` )
    ( nurl_print `cnt=` ) ( nurl_print ( nurl_str_int cnt ) ) ( nurl_print `\n` )

    // ── Sorted output via map_iter → Vec[s] of keys (deterministic) ──
    : ( Vec s ) keys ( vec_new [s] )
    : ( @ ?( Pair s i ) i ) it2 ( map_iter [s i] m )
    : ~ b d2 F
    ~ ! d2 {
        : ?( Pair s i ) g ( it2 0 )
        ?? g {
            T p → { ( vec_push [s] keys ( pair_first [s i] p ) ) }
            F → { = d2 T }
        }
    }
    ( it2 1 )
    : ( @ i s s ) cmp_s_cl \ s a s b → i { ^ ( cmp_str a b ) }
    ( sort_by [s] keys cmp_s_cl )
    ( nurl_print `keys=` )
    : ~ i k 0
    ~ < k ( vec_len [s] keys ) {
        : ?s g ( vec_get [s] keys k )
        ?? g {
            T x → { ( nurl_print x ) ( nurl_print ` ` ) }
            F → {}
        }
        = k + k 1
    }
    ( nurl_print `\n` )
    ( vec_free [s] keys )

    // ── Mid-walk abandon: state must still free via cmd=1 ──
    : ( @ ?( Pair s i ) i ) it3 ( map_iter [s i] m )
    : ?( Pair s i ) g3 ( it3 0 )
    ?? g3 {
        T p → { ( nurl_print `peek_one=` ) ( nurl_print ( pair_first [s i] p ) ) ( nurl_print `\n` ) }
        F → {}
    }
    ( it3 1 )

    // ── Empty-map iteration is harmless ──
    : ( HashMap s i ) empty ( map_new [s i] )
    : ( @ ?( Pair s i ) i ) it4 ( map_iter [s i] empty )
    : ?( Pair s i ) g4 ( it4 0 )
    ?? g4 {
        T p → { ( nurl_print `unexpected\n` ) }
        F → { ( nurl_print `empty=ok\n` ) }
    }
    ( it4 1 )
    ( map_free [s i] empty )

    ( map_free [s i] m )
    ( nurl_print `done\n` )
    ^ 0
}
