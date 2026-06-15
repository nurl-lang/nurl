// sim_job.nu — §7.5 Phase 13 chaos-harness scenario for the KEYSTONE (dist/job).
// Drives the REAL job codec + ring ownership + handler execution + idempotent
// result store over dist/sim's deterministic bus (no sockets, no transport):
//   (1) a task COMPLETES across 40% packet loss — the submitter retries until
//       its result store records the answer; the owner executes idempotently,
//       so retries are harmless and the recorded result is correct;
//   (2) a partition isolates the submitter from the key's owner — the task does
//       NOT complete while split; sim_heal_all reconverges and it completes.
// Seeded → byte-reproducible; the assertions can genuinely fail.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`
$ `stdlib/dist/sim.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ pk i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }
@ bytes4 i a i b i c i d → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( vec_push [u] v # u a ) ( vec_push [u] v # u b ) ( vec_push [u] v # u c ) ( vec_push [u] v # u d ) ^ v }
@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}
@ node ( Vec s ) nodes i i → *JobNode { ^ # *JobNode ?? ( vec_get [s] nodes i ) { T x → x F → # s 0 } }

// task kind 0: result = (sum of payload bytes) & 255, as a 1-byte vector
@ sum_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : ~ i s 0
        : i nn ( vec_len [u] p )
        : ~ i k 0
        ~ < k nn { = s + s ?? ( vec_get [u] p k ) { T x → # i x F → 0 } = k + k 1 }
        : ( Vec u ) r ( vec_new [u] )
        ( vec_push [u] r # u & s 255 )
        ^ r
    }
}

// map a pubkey back to its node index (-1 if none)
@ pk_to_idx ( Vec s ) nodes i nn ( Vec u ) target → i {
    : ~ i found -1
    : ~ i k 0
    ~ & == found -1 < k nn { ? ( veq . ( node nodes k ) self_pk target ) { = found k } {} = k + k 1 }
    ^ found
}

// current owning node index for a key (via the shared ring)
@ owner_idx_of *Ring ring ( Vec s ) nodes i nn ( Vec u ) key → i {
    : ~ i idx -1
    ?? ( ring_owner_pk ring key ) { T o → { = idx ( pk_to_idx nodes nn o ) ( vec_free [u] o ) } F → {} }
    ^ idx
}

// submitter side over the bus: route a SUBMIT to the key's current owner.
@ submit_over_bus *SimNet net *Ring ring ( Vec s ) nodes i nn i submitter i tid i kind ( Vec u ) key ( Vec u ) payload i now → v {
    : i oidx ( owner_idx_of ring nodes nn key )
    ? < oidx 0 { ^ v } {}
    : *JobNode sn ( node nodes submitter )
    : ( Vec u ) msg ( job_build_submit tid kind . sn self_pk key payload )
    ( sim_send net submitter oidx msg now )
    ( vec_free [u] msg )
}

// deliver every due message: owner executes a SUBMIT and replies a RESULT
// (forwarding if the ring moved); a RESULT is recorded idempotently.
@ deliver_due *SimNet net *Ring ring ( Vec s ) nodes i nn i now → v {
    : ( Vec s ) due ( sim_due net now )
    : i dn ( vec_len [s] due )
    : ~ i k 0
    ~ < k dn {
        : s mp ?? ( vec_get [s] due k ) { T x → x F → # s 0 }
        ? != # i mp 0 {
            : *SimMsg sm # *SimMsg mp
            : JobMsg m ( jobmsg_decode . sm bytes )
            ? == . m mtype ( job_submit_t ) {
                : *JobNode dn2 ( node nodes . sm dst )
                ? ( job_owns dn2 . m key ) {
                    : ( Vec u ) res ( __job_execute dn2 . m kind . m payload )
                    : i sidx ( pk_to_idx nodes nn . m submitter )
                    : ( Vec u ) reply ( job_build_result . m task_id res )
                    ? >= sidx 0 { ( sim_send net . sm dst sidx reply now ) } {}
                    ( vec_free [u] res ) ( vec_free [u] reply )
                } {
                    // ring moved: forward to the current owner
                    : i oidx ( owner_idx_of ring nodes nn . m key )
                    ? & >= oidx 0 != oidx . sm dst {
                        : ( Vec u ) fwd ( job_build_submit . m task_id . m kind . m submitter . m key . m payload )
                        ( sim_send net . sm dst oidx fwd now )
                        ( vec_free [u] fwd )
                    } {}
                }
            } {}
            ? == . m mtype ( job_result_t ) { ( job_on_result ( node nodes . sm dst ) m ) } {}
            ( jobmsg_free m )
            ( sim_msg_free sm )
        } {}
        = k + k 1
    }
    ( vec_free [s] due )
}

@ make_nodes *Ring ring i nn → ( Vec s ) {
    : ( Vec s ) nodes ( vec_new [s] )
    : ~ i i 0
    ~ < i nn {
        : ( Vec u ) selfpk ( pk i )
        : *JobNode n ( job_node_new # s 0 # s ring selfpk i )   // transport=0; pure paths only
        ( job_register n 0 ( sum_handler ) )
        ( vec_free [u] selfpk )
        ( vec_push [s] nodes # s n )
        = i + i 1
    }
    ^ nodes
}
@ free_nodes ( Vec s ) nodes i nn → v {
    : ~ i i 0 ~ < i nn { ( job_node_free ( node nodes i ) ) = i + i 1 }
    ( vec_free [s] nodes )
}

// find a key (bytes4 s,s,s,s) whose owner is NOT `avoid`; returns the seed.
@ find_key_not_owned_by *Ring ring ( Vec s ) nodes i nn i avoid → i {
    : ~ i found -1
    : ~ i s 1
    ~ & == found -1 < s 200 {
        : ( Vec u ) key ( bytes4 s s s s )
        : i oidx ( owner_idx_of ring nodes nn key )
        ? & >= oidx 0 != oidx avoid { = found s } {}
        ( vec_free [u] key )
        = s + s 1
    }
    ^ found
}

@ main → i {
    : i nn 4
    : *Ring ring ( ring_new )
    : ~ i mi 0
    ~ < mi nn { : ( Vec u ) mp ( pk mi ) ( ring_add_member ring mp 32 ) ( vec_free [u] mp ) = mi + mi 1 }

    // ── (1) job completes across 40% packet loss, via retry ──────────
    : *SimNet net ( sim_net_new nn 24680 40 1 2 )
    : ( Vec s ) nodes ( make_nodes ring nn )
    : i kseed ( find_key_not_owned_by ring nodes nn 0 )
    ( pb `found a key owned by a remote node: ` >= kseed 0 )
    : ( Vec u ) key ( bytes4 kseed kseed kseed kseed )
    : ( Vec u ) pl ( bytes4 1 2 3 4 )                 // sum = 10
    : *JobNode s0 ( node nodes 0 )
    : i tid ( __job_unique s0 )
    : ~ i now 0
    : ~ i r 0
    ~ < r 80 {
        = now + now 1
        ? ! ( job_has s0 tid ) { ( submit_over_bus net ring nodes nn 0 tid 0 key pl now ) } {}   // retry until done
        ( deliver_due net ring nodes nn now )
        = r + r 1
    }
    ( pb `lossy: task completed (result recorded on submitter): ` ( job_has s0 tid ) )
    ( pb `lossy: recorded result is sum=10: ` ?? ( job_await s0 tid ) { T rr → { : b ok == ?? ( vec_get [u] rr 0 ) { T x → # i x F → -1 } 10 ( vec_free [u] rr ) ok } F → F } )
    ( pb `lossy: messages were actually dropped: ` > ( sim_dropped net ) 0 )
    ( free_nodes nodes nn ) ( sim_net_free net )

    // ── (2) partition isolates submitter from owner; heal completes ──
    : *SimNet net2 ( sim_net_new nn 13579 0 1 0 )     // no random drop; clean partition
    : ( Vec s ) nd ( make_nodes ring nn )
    : i kseed2 ( find_key_not_owned_by ring nd nn 0 )
    : ( Vec u ) key2 ( bytes4 kseed2 kseed2 kseed2 kseed2 )
    : i oidx ( owner_idx_of ring nd nn key2 )
    ( sim_partition net2 0 oidx )                      // cut submitter↔owner both ways
    : *JobNode sn0 ( node nd 0 )
    : i tid2 ( __job_unique sn0 )
    : ~ i now2 0
    : ~ i r2 0
    ~ < r2 30 {
        = now2 + now2 1
        ? ! ( job_has sn0 tid2 ) { ( submit_over_bus net2 ring nd nn 0 tid2 0 key2 pl now2 ) } {}
        ( deliver_due net2 ring nd nn now2 )
        = r2 + r2 1
    }
    ( pb `partition: task does NOT complete while split: ` ! ( job_has sn0 tid2 ) )
    ( sim_heal_all net2 )
    : ~ i r3 0
    ~ < r3 30 {
        = now2 + now2 1
        ? ! ( job_has sn0 tid2 ) { ( submit_over_bus net2 ring nd nn 0 tid2 0 key2 pl now2 ) } {}
        ( deliver_due net2 ring nd nn now2 )
        = r3 + r3 1
    }
    ( pb `after heal: task completes: ` ( job_has sn0 tid2 ) )
    ( pb `after heal: recorded result is sum=10: ` ?? ( job_await sn0 tid2 ) { T rr → { : b ok == ?? ( vec_get [u] rr 0 ) { T x → # i x F → -1 } 10 ( vec_free [u] rr ) ok } F → F } )
    ( vec_free [u] key2 )
    ( free_nodes nd nn ) ( sim_net_free net2 )

    ( vec_free [u] key ) ( vec_free [u] pl )
    ( ring_free ring )
    ^ 0
}
