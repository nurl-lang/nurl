// stdlib/dist/job.nu — distributed work dispatch (§7.5 Phase 11, THE KEYSTONE).
//
// Everything beneath this already exists: the consistent-hash ring decides who
// owns a key, net/transport carries opaque bytes by pubkey, dist/crdt records
// results idempotently, the cluster layer retries. This module is what turns
// distributed STATE into distributed COMPUTATION.
//
// Model: submit a task keyed by `k`; `ring_owner(k)` executes it via a
// registered handler; the result is returned to the submitter and recorded so
// duplicate delivery is harmless.
//
//   * job_submit(key, kind, payload) → task_id  — routes to ring_owner(key);
//     if this node owns the key it runs the handler locally.
//   * the owner decodes → runs the kind's handler → replies a RESULT to the
//     submitter; results are recorded by task_id (idempotent → at-least-once
//     + retry stays safe).
//   * job_pump drains inbound SUBMIT/RESULT; job_await(task_id) returns the
//     recorded result.
//   * CAPABILITY DOMAINS: job_set_ring(kind, ring) scopes a task kind to its
//     own routing ring (e.g. only GPU-capable workers) — submit, ownership and
//     forwarding for that kind all resolve against the scoped ring, so a task
//     can never land on (or re-home to) a node outside its domain. Kinds
//     without a scoped ring use the main ring, unchanged.
//   * OWNERSHIP MOVED MID-FLIGHT: a node that receives a SUBMIT for a key it
//     no longer owns (the ring changed) FORWARDS it to the current owner
//     rather than dropping or mis-executing it — so killing a worker re-homes
//     its keys and the job still completes.
//
// Invariant (compute): a key is owned by exactly one node per epoch; a task
// executes at-least-once; its effect is idempotent (pure handlers) or leased
// (§7.5 Phase 12, dist/lease.nu — for side-effecting handlers).
//
// The protocol codec, handler registry, routing decision and result store are
// pure; only job_submit / job_pump touch the transport.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/net/transport.nu`

@ job_submit_t → i { ^ 1 }

@ job_result_t → i { ^ 2 }

@ __job_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ __job_veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

// ── wire protocol ────────────────────────────────────────────────
// SUBMIT: [1][task_id:8][kind:4][slen:2][submitter_pk][klen:2][key][payload…]
// RESULT: [2][task_id:8][payload…]
// payload runs to the end of the buffer (transport delivers whole messages).

: JobMsg {
    i mtype
    i task_id
    i kind
    ( Vec u ) submitter
    ( Vec u ) key
    ( Vec u ) payload
}

@ jobmsg_free JobMsg m → v {
    ( vec_free [u] . m submitter )
    ( vec_free [u] . m key )
    ( vec_free [u] . m payload )
}

@ __job_put_blob ( Vec u ) b ( Vec u ) blob → v {
    ( bytes_push_u16_be b # u16 ( vec_len [u] blob ) )
    ( vec_extend [u] b blob )
}

@ job_build_submit i task_id i kind ( Vec u ) submitter ( Vec u ) key ( Vec u ) payload → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ( job_submit_t ) )
    ( bytes_push_u64_be b # u64 task_id )
    ( bytes_push_u32_be b # u32 kind )
    ( __job_put_blob b submitter )
    ( __job_put_blob b key )
    ( vec_extend [u] b payload )
    ^ b
}

@ job_build_result i task_id ( Vec u ) payload → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ( job_result_t ) )
    ( bytes_push_u64_be b # u64 task_id )
    ( vec_extend [u] b payload )
    ^ b
}

: JCur { ( Vec u ) buf i off }

@ __jc_u8 * JCur c → i { : i v ?? ( vec_get [u] . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 1 ^ v }

@ __jc_u16 * JCur c → i { : i v ?? ( bytes_read_u16_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 2 ^ v }

@ __jc_u32 * JCur c → i { : i v ?? ( bytes_read_u32_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 4 ^ v }

@ __jc_u64 * JCur c → i { : i v ?? ( bytes_read_u64_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 8 ^ v }

@ __jc_blob * JCur c i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [u] . c buf + . c off k ) { T x → ( vec_push [u] o x ) F → {} } = k + k 1 }
    = . c off + . c off n
    ^ o
}

@ __jc_rest * JCur c → ( Vec u ) {
    : i n ( vec_len [u] . c buf )
    ^ ( __jc_blob c - n . c off )
}

@ jobmsg_decode ( Vec u ) buf → JobMsg {
    : *JCur c # *JCur ( nurl_alloc Z JCur )
    = . c buf buf
    = . c off 0
    : i mtype ( __jc_u8 c )
    : i task_id ( __jc_u64 c )
    : ~ i kind 0
    : ~ ( Vec u ) submitter ( vec_new [u] )
    : ~ ( Vec u ) key ( vec_new [u] )
    ? == mtype ( job_submit_t ) {
        = kind ( __jc_u32 c )
        : i slen ( __jc_u16 c )
        ( vec_free [u] submitter )
        = submitter ( __jc_blob c slen )
        : i klen ( __jc_u16 c )
        ( vec_free [u] key )
        = key ( __jc_blob c klen )
    } {}
    : ( Vec u ) payload ( __jc_rest c )
    ( nurl_free # s c )
    ^ @ JobMsg { mtype task_id kind submitter key payload }
}

// ── node: ring + transport + handler registry + result store ─────

: JobHandler {
    i kind
    ( @ ( Vec u ) ( Vec u ) ) fn
}

// A capability-scoped routing ring for one task kind (e.g. only GPU-capable
// workers). Kinds without an entry route on the node's main ring.
: JobKindRing {
    i kind
    s ring  // *Ring (caller-owned; not freed here)
}
: JobResult {
    i task_id
    ( Vec u ) result
}
: JobNode {
    s transport  // *Transport (caller-owned; not freed here)
    s ring  // *Ring     (caller-owned; not freed here)
    ( Vec u ) self_pk
    i replica  // this node's stable replica id → unique task ids
    i next_task
    ( Vec s ) handlers  // *JobHandler
    ( Vec s ) results  // *JobResult (idempotent by task_id)
    ( Vec s ) kind_rings  // *JobKindRing (per-kind routing domains)
}

@ job_node_new s transport s ring ( Vec u ) self_pk i replica → *JobNode {
    : *JobNode n # *JobNode ( nurl_alloc Z JobNode )
    = . n transport transport
    = . n ring ring
    = . n self_pk ( __job_cpy self_pk )
    = . n replica replica
    = . n next_task 0
    = . n handlers ( vec_new [s] )
    = . n results ( vec_new [s] )
    = . n kind_rings ( vec_new [s] )
    ^ n
}

@ job_node_free * JobNode n → v {
    ( vec_free [u] . n self_pk )
    : i hn ( vec_len [s] . n handlers )
    : ~ i k 0
    ~ < k hn {
        : s pp ?? ( vec_get [s] . n handlers k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *JobHandler jh # *JobHandler pp
            : ( @ ( Vec u ) ( Vec u ) ) hf . jh fn
            : *u env # *u hf 1
            ? != # i env 0 { ( nurl_free # s env ) } {}
            ( nurl_free # s jh )
        } {}
        = k + k 1
    }
    ( vec_free [s] . n handlers )
    : i rn ( vec_len [s] . n results )
    : ~ i j 0
    ~ < j rn {
        : s pp ?? ( vec_get [s] . n results j ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *JobResult jr # *JobResult pp ( vec_free [u] . jr result ) ( nurl_free # s jr ) } {}
        = j + j 1
    }
    ( vec_free [s] . n results )
    : i kn ( vec_len [s] . n kind_rings )
    : ~ i q 0
    ~ < q kn {
        : s pp ?? ( vec_get [s] . n kind_rings q ) { T x → x F → # s 0 }
        ? != # i pp 0 { ( nurl_free pp ) } {}
        = q + q 1
    }
    ( vec_free [s] . n kind_rings )
    ( nurl_free # s n )
}

// Register a handler for a task kind: payload bytes → result bytes.
@ job_register * JobNode n i kind ( @ ( Vec u ) ( Vec u ) ) fn → v {
    : *JobHandler jh # *JobHandler ( nurl_alloc Z JobHandler )
    = . jh kind kind
    = . jh fn fn
    ( vec_push [s] . n handlers # s jh )
}

// Scope a task kind to a routing ring (a capability domain): submit, ownership
// and mid-flight forwarding for that kind all resolve against `ring` instead of
// the node's main ring. EVERY node in the cluster must scope the same kind to
// an equivalently-built ring, or forwarding re-homes across domains. The ring
// is caller-owned (like the main ring) and must outlive the node. Setting a
// kind twice replaces the ring (e.g. after rebuilding the domain on churn).
@ job_set_ring * JobNode n i kind s ring → v {
    : i kn ( vec_len [s] . n kind_rings )
    : ~ b done F : ~ i k 0
    ~ & ! done < k kn {
        : s pp ?? ( vec_get [s] . n kind_rings k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *JobKindRing kr # *JobKindRing pp
            ? == . kr kind kind { = . kr ring ring = done T } {}
        } {}
        = k + k 1
    }
    ? ! done {
        : *JobKindRing kr # *JobKindRing ( nurl_alloc Z JobKindRing )
        = . kr kind kind
        = . kr ring ring
        ( vec_push [s] . n kind_rings # s kr )
    } {}
}

// The routing ring for a kind: its scoped ring if set, else the main ring.
@ __job_ring_for * JobNode n i kind → s {
    : i kn ( vec_len [s] . n kind_rings )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k kn {
        : s pp ?? ( vec_get [s] . n kind_rings k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *JobKindRing kr # *JobKindRing pp ? == . kr kind kind { = found . kr ring } {} } {}
        = k + k 1
    }
    ^ ? != # i found 0 found . n ring
}

@ __job_handler * JobNode n i kind → s {
    : i hn ( vec_len [s] . n handlers )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k hn {
        : s pp ?? ( vec_get [s] . n handlers k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *JobHandler jh # *JobHandler pp ? == . jh kind kind { = found pp } {} } {}
        = k + k 1
    }
    ^ found
}

// Run the registered handler for a kind (empty Vec if none registered).
@ _job_execute * JobNode n i kind ( Vec u ) payload → ( Vec u ) {
    : s hp ( __job_handler n kind )
    ? == # i hp 0 { ^ ( vec_new [u] ) } {}
    : *JobHandler jh # *JobHandler hp
    : ( @ ( Vec u ) ( Vec u ) ) h . jh fn
    ^ ( h payload )
}

// Record a result by task_id, idempotently (a re-delivered RESULT is a no-op).
@ __job_record * JobNode n i task_id ( Vec u ) result → v {
    : i rn ( vec_len [s] . n results )
    : ~ b have F : ~ i k 0
    ~ & ! have < k rn {
        : s pp ?? ( vec_get [s] . n results k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *JobResult jr # *JobResult pp ? == . jr task_id task_id { = have T } {} } {}
        = k + k 1
    }
    ? have { ^ v } {}
    : *JobResult jr # *JobResult ( nurl_alloc Z JobResult )
    = . jr task_id task_id
    = . jr result ( __job_cpy result )
    ( vec_push [s] . n results # s jr )
}

// Has a result for this task_id been recorded?
@ job_has * JobNode n i task_id → b {
    : i rn ( vec_len [s] . n results )
    : ~ b have F : ~ i k 0
    ~ & ! have < k rn {
        : s pp ?? ( vec_get [s] . n results k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *JobResult jr # *JobResult pp ? == . jr task_id task_id { = have T } {} } {}
        = k + k 1
    }
    ^ have
}

// The recorded result for a task_id (copied), or None.
@ job_await * JobNode n i task_id → ?( Vec u ) {
    : i rn ( vec_len [s] . n results )
    : ~ ? ( Vec u ) out @ ?( Vec u ) { F # ( Vec u ) 0 }
    : ~ b got F
    : ~ i k 0
    ~ & ! got < k rn {
        : s pp ?? ( vec_get [s] . n results k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *JobResult jr # *JobResult pp
            ? == . jr task_id task_id { = out @ ?( Vec u ) { T ( __job_cpy . jr result ) } = got T } {}
        } {}
        = k + k 1
    }
    ^ out
}

// The current owner pubkey for a key (from the live ring), copied or None.
@ job_owner_pk * JobNode n ( Vec u ) key → ?( Vec u ) { ^ ( ring_owner_pk # *Ring . n ring key ) }

// Does this node own `key` on the given ring?
@ __job_owns_ring * JobNode n s ring ( Vec u ) key → b {
    : ?( Vec u ) o ( ring_owner_pk # *Ring ring key )
    ^ ?? o { T pk → { : b same ( __job_veq pk . n self_pk ) ( vec_free [u] pk ) same } F → F }
}

// Does this node currently own `key`? (main ring — kind-agnostic)
@ job_owns * JobNode n ( Vec u ) key → b {
    ^ ( __job_owns_ring n . n ring key )
}

@ _job_unique * JobNode n → i {
    : i id + * . n replica 1000000000 . n next_task
    = . n next_task + . n next_task 1
    ^ id
}

// ── dispatch (transport adapter) ─────────────────────────────────

// Submit a task keyed by `key`. If this node owns the key it runs the handler
// immediately and records the result locally; otherwise it routes a SUBMIT to
// the current owner. Returns the task_id to await.
@ job_submit * JobNode n i kind ( Vec u ) key ( Vec u ) payload → i {
    : i tid ( _job_unique n )
    : s ring ( __job_ring_for n kind )
    ? ( __job_owns_ring n ring key ) {
        : ( Vec u ) res ( _job_execute n kind payload )
        ( __job_record n tid res )
        ( vec_free [u] res )
    } {
        : ?( Vec u ) o ( ring_owner_pk # *Ring ring key )
        ?? o {
            T owner → {
                : ( Vec u ) msg ( job_build_submit tid kind . n self_pk key payload )
                ?? ( transport_send # *Transport . n transport owner msg ) { T _ → {} F _ → {} }
                ( vec_free [u] msg )
                ( vec_free [u] owner )
            }
            F → {}
        }
    }
    ^ tid
}

// Owner side: a SUBMIT arrived. Execute if we own the key and reply a RESULT
// to the submitter; otherwise FORWARD to the current owner (re-home).
@ job_on_submit * JobNode n JobMsg m → v {
    : s ring ( __job_ring_for n . m kind )
    ? ( __job_owns_ring n ring . m key ) {
        : ( Vec u ) res ( _job_execute n . m kind . m payload )
        : ( Vec u ) reply ( job_build_result . m task_id res )
        ?? ( transport_send # *Transport . n transport . m submitter reply ) { T _ → {} F _ → {} }
        ( vec_free [u] res )
        ( vec_free [u] reply )
    } {
        : ?( Vec u ) o ( ring_owner_pk # *Ring ring . m key )
        ?? o {
            T owner → {
                ? ! ( __job_veq owner . n self_pk ) {
                    : ( Vec u ) fwd ( job_build_submit . m task_id . m kind . m submitter . m key . m payload )
                    ?? ( transport_send # *Transport . n transport owner fwd ) { T _ → {} F _ → {} }
                    ( vec_free [u] fwd )
                } {}
                ( vec_free [u] owner )
            }
            F → {}
        }
    }
}

// Submitter side: a RESULT arrived → record it (idempotent).
@ job_on_result * JobNode n JobMsg m → v { ( __job_record n . m task_id . m payload ) }

// Drain inbound transport messages, dispatching SUBMIT / RESULT.
@ job_pump * JobNode n i max → v {
    : ~ b more T
    ~ more {
        ?? ( transport_recv # *Transport . n transport max ) {
            T tm → {
                : JobMsg m ( jobmsg_decode . tm payload )
                ? == . m mtype ( job_submit_t ) { ( job_on_submit n m ) } {}
                ? == . m mtype ( job_result_t ) { ( job_on_result n m ) } {}
                ( jobmsg_free m )
                ( transport_msg_free tm )
            }
            F → { = more F }
        }
    }
}
