// dist_heartbeat_thread.nu — the heartbeat thread's view of the node
// (stdlib/dist/heartbeat.nu) while the data plane changes the table.
//
// heartbeat_start used to hand its thread the membership table and a mutex
// the caller had to remember to take around its own changes; nothing made
// it. The thread now holds only the node's liveness (pktable_liveness): a
// copy of the self pubkey and the table's incarnation counter, an Atomic.
// Here a thread builds heartbeat payloads from it while main grows the
// table to 2000 members and refutes, with no lock anywhere: every payload
// decodes to this node alive, the incarnations it sees never go down, and
// the last one is the final incarnation. (Under ASan, run_san_tests.sh,
// a shared table would show the realloc race; this shares nothing.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/dist/heartbeat.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mkpk i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ( vec_push [u] v # u & seed 255 ) ( vec_push [u] v # u & / seed 256 255 )
    ~ < k 30 { ( vec_push [u] v # u k ) = k + k 1 }
    ^ v
}

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T x → # i x F → -1 } ?? ( vec_get [u] b k ) { T y → # i y F → -2 } { = e F } {} = k + k 1 }
    ^ e
}

@ main → i {
    : ( Vec u ) me ( mkpk 50 )
    : PkMemberTable t ( pktable_new me 1000 5000 3 8 )
    : PkLiveness lv ( pktable_liveness t )
    : Atomic done ( atomic_new 0 )
    : Atomic seen ( atomic_new 0 )  // the highest incarnation the thread saw
    : Atomic bad ( atomic_new 0 )  // payloads that were not this node alive, or went down
    : Atomic sent ( atomic_new 0 )

    : ( @ v ) beat \ → v {
        : ~ i last 0
        : ~ b more T
        ~ more {
            = more == ( atomic_load done ) 0
            : ( Vec u ) p ( heartbeat_payload_of lv )
            : PkMsg m ( pkmsg_decode p )
            ?? ( vec_get [PkMember] . m gossip 0 ) {
                T f → {
                    ? | | != . f state ( pk_alive ) < . f incarnation last != ( vec_len [u] . f pubkey ) 32 { : i _b ( atomic_add bad 1 ) } {}
                    = last . f incarnation
                }
                F → { : i _b ( atomic_add bad 1 ) }
            }
            : i _s ( atomic_add sent 1 )
        }
        ( atomic_store seen last )
    }

    : !Thread ThreadErr tr ( thread_spawn beat )
    ?? tr {
        T th → {
            : ~ i k 0
            ~ < k 2000 {
                : b _a ( pktable_apply t ( mkpk + 100 k ) 0 1 k )
                ? == 0 % k 200 { : b _r ( pktable_refute t ( pktable_self_incarnation t ) ) } {}
                = k + k 1
            }
            ( atomic_store done 1 )
            ( thread_join th )
        }
        F _ → { ( puts `spawn failed` ) }
    }

    ( pb `table grew to 2000 members: ` == ( pktable_count t ) 2000 )
    ( pb `ten refutes, incarnation 10: ` == ( pktable_self_incarnation t ) 10 )
    ( pb `every payload this node alive, never going down: ` == ( atomic_load bad ) 0 )
    ( pb `the last payload carries incarnation 10: ` == ( atomic_load seen ) 10 )
    ( pb `the thread sent payloads: ` > ( atomic_load sent ) 0 )

    // The liveness payload is the table's payload, byte for byte.
    : ( Vec u ) a ( heartbeat_payload t )
    : ( Vec u ) b ( heartbeat_payload_of ( pktable_liveness t ) )
    ( pb `liveness payload = table payload: ` ( veq a b ) )
    ^ 0
}
