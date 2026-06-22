// stdlib/ext/dchannel.nu — DChannel[A]: a distributed channel that
// mirrors the local std/channel.nu API across an address-space boundary.
//
// **Phase 2 (TODO §7.2)** of the distributed-computing track. The headline
// "location transparency" feature: the same send/recv shape as a local
// Channel[A], except the two ends live in different processes / hosts.
//
// ── The idea: move to another address space ──────────────────────────
//
// Sending a value on a DChannel is a MOVE. The value is serialized onto
// the wire, materialized in the *remote* process's queue, and released
// locally — it genuinely ceases to exist here and begins to exist there.
// Receiving materializes a fresh owned value out of the wire. This is the
// single-owner model extended over the network, which is unusually clean
// to express because NURL already tracks ownership locally.
//
// Built on ext/cluster.nu, so it inherits the resilience layer for free:
// each operation is a `call_remote_with` carrying a RetryPolicy (transport
// retry + backoff). Backpressure rides on top — a bounded remote queue
// makes a blocking send wait for space.
//
// ── Codecs ───────────────────────────────────────────────────────────
//
// DChannel[A] is generic over the element type A. Because the wire is
// JSON, the channel carries three closures fixing A's (de)serialization
// and ownership, supplied once at open:
//
//   enc  :: ( @ Json A )   — BORROW A, return an owned JSON snapshot
//                            (must NOT free A; the channel frees it)
//   dec  :: ( @ A Json )   — BORROW a JSON value, return a fresh owned A
//   drop :: ( @ v A )      — release an A (no-op for scalars)
//
// `dchan_open_json` supplies identity codecs for A = Json.
//
// ── Ownership contract (mirrors local chan_send, with one twist) ──────
//
//   dchan_send   — blocking; on Ok the value is CONSUMED (drop'd). On a
//                  closed channel returns F and the caller KEEPS the value
//                  (same as local). A full remote queue blocks (waits).
//   dchan_try_send — non-blocking; DSendOk consumes, DSendFull/Closed/Err
//                  leave the value with the caller.
//   dchan_recv   — blocking; None only when the remote channel is closed
//                  AND drained (same as local).
//   dchan_try_recv — non-blocking; None when momentarily empty.
//
// ── API ──────────────────────────────────────────────────────────────
//
//   Server (host the queues):
//     ( dstore_new i default_cap )                    → DStore
//     ( dstore_declare DStore s s name i cap )         → v
//     ( dstore_free DStore s )                         → v
//     ( dchan_register DStore s Registry r )           → v
//     ( dchan_serve s host i port DStore s )           → !v NetErr
//
//   Client (generic over A):
//     ( dchan_open [A] Node node s name RetryPolicy pol i poll_ms
//                      ( @ Json A ) enc ( @ A Json ) dec ( @ v A ) drop ) → ( DChannel A )
//     ( dchan_open_json Node node s name RetryPolicy pol i poll_ms )      → ( DChannel Json )
//     ( dchan_free   [A] ( DChannel A ) ch )           → v
//     ( dchan_send   [A] ( DChannel A ) ch A v )       → b
//     ( dchan_try_send [A] ( DChannel A ) ch A v )     → DSend
//     ( dchan_recv   [A] ( DChannel A ) ch )           → ?A
//     ( dchan_try_recv [A] ( DChannel A ) ch )         → ?A
//     ( dchan_close  [A] ( DChannel A ) ch )           → v
//     ( dchan_len    [A] ( DChannel A ) ch )           → i

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/cluster.nu`

// Wire fn-ids registered on the cluster Registry.
@ __wire_send → s { ^ `dchan/send` }

@ __wire_recv → s { ^ `dchan/recv` }

@ __wire_close → s { ^ `dchan/close` }

@ __wire_len → s { ^ `dchan/len` }

// ── Server: bounded, thread-safe per-name Json queues ────────────────
//
// A DQueue is heap-allocated and referenced by pointer from the store's
// entry Vec, so its scalar `closed` flag is shared by every accessor
// (a by-value copy would not propagate the mutation). `cap` 0 = unbounded.

: DQueue {
    Mutex m
    ( Vec Json ) items
    i cap
    i closed
}

: DStoreEntry {
    String name
    s q  // *DQueue
}

: DStore {
    Mutex m
    ( Vec DStoreEntry ) entries
    i default_cap
}

@ dstore_new i default_cap → DStore {
    ^ @ DStore { ( mutex_new ) ( vec_new [DStoreEntry] ) default_cap }
}

@ __dq_new i cap → *DQueue {
    : *DQueue q # *DQueue ( nurl_alloc Z DQueue )
    = . q m ( mutex_new )
    = . q items ( vec_new [Json] )
    = . q cap cap
    = . q closed 0
    ^ q
}

// Find an entry index by name. Caller must hold the store mutex.
@ __dstore_find DStore s s name → i {
    : i n ( vec_len [DStoreEntry] . s entries )
    : ~ i found - 0 1
    : ~ b done F
    : ~ i k 0
    ~ & ! done < k n {
        : ?DStoreEntry ek ( vec_get [DStoreEntry] . s entries k )
        ?? ek {
            T e → {
                ? != 0 ( nurl_str_eq ( string_data . e name ) name ) {
                    = found k
                    = done T
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

// Return the (heap) DQueue for `name`, creating it at the store's default
// capacity if absent. Caller must hold the store mutex.
@ __dstore_get_or_create DStore s s name → *DQueue {
    : i idx ( __dstore_find s name )
    ? >= idx 0 {
        : ?DStoreEntry ek ( vec_get [DStoreEntry] . s entries idx )
        ^ ?? ek {
            T e → # *DQueue . e q
            F → ( __dq_new . s default_cap )  // unreachable
        }
    } {}
    : *DQueue q ( __dq_new . s default_cap )
    : DStoreEntry e @ DStoreEntry { ( string_from name ) # s q }
    ( vec_push [DStoreEntry] . s entries e )
    ^ q
}

// Pre-create a channel with an explicit capacity (otherwise channels are
// created lazily at default_cap on first use).
@ dstore_declare DStore s s name i cap → v {
    ( mutex_lock . s m )
    ? < ( __dstore_find s name ) 0 {
        : DStoreEntry e @ DStoreEntry { ( string_from name ) # s ( __dq_new cap ) }
        ( vec_push [DStoreEntry] . s entries e )
    } {}
    ( mutex_unlock . s m )
}

@ __dq_free * DQueue q → v {
    ( vec_free_with [Json] . q items \ Json j → v { ( json_free j ) } )
    ( mutex_free . q m )
    ( nurl_free # s q )
}

@ dstore_free DStore s → v {
    ( vec_free_with [DStoreEntry] . s entries
    \ DStoreEntry e → v {
        ( string_free . e name )
        ( __dq_free # *DQueue . e q )
    } )
    ( mutex_free . s m )
}

// ── Server: result-envelope helpers ──────────────────────────────────

@ __status_env s status → Json {
    : Json r ( json_obj_new )
    ( json_obj_set r `status` ( json_str_lit status ) )
    ^ r
}

// ── Server: the four handlers ────────────────────────────────────────

@ __dchan_h_send DStore store Json args → !Json ClusterErr {
    : ?Json chj ( json_obj_get args `ch` )  // borrow
    : s name ?? chj { T x → ( json_as_str x ) F → `` }
    : ?Json vj ( json_obj_get args `v` )  // borrow

    ( mutex_lock . store m )
    : *DQueue q ( __dstore_get_or_create store name )
    ( mutex_unlock . store m )

    ( mutex_lock . q m )
    : Json res ? != 0 . q closed {
        ( __status_env `closed` )
    } {
        ? & > . q cap 0 >= ( vec_len [Json] . q items ) . q cap {
            ( __status_env `full` )
        } {
            // Materialize the value in this address space (deep copy out
            // of the borrowed args), then enqueue.
            : Json owned ?? vj { T v → ( json_clone v ) F → ( json_null ) }
            ( vec_push [Json] . q items owned )
            ( __status_env `ok` )
        }
    }
    ( mutex_unlock . q m )
    ^ @ !Json ClusterErr { T res }
}

@ __dchan_h_recv DStore store Json args → !Json ClusterErr {
    : ?Json chj ( json_obj_get args `ch` )
    : s name ?? chj { T x → ( json_as_str x ) F → `` }

    ( mutex_lock . store m )
    : *DQueue q ( __dstore_get_or_create store name )
    ( mutex_unlock . store m )

    ( mutex_lock . q m )
    : Json res ? > ( vec_len [Json] . q items ) 0 {
        : Json env ( __status_env `ok` )
        : ?Json popped ( vec_remove [Json] . q items 0 )  // owned
        ?? popped {
            T pv → { ( json_obj_set env `v` pv ) }  // move into env
            F → {}
        }
        env
    } {
        ? != 0 . q closed { ( __status_env `closed` ) } { ( __status_env `empty` ) }
    }
    ( mutex_unlock . q m )
    ^ @ !Json ClusterErr { T res }
}

@ __dchan_h_close DStore store Json args → !Json ClusterErr {
    : ?Json chj ( json_obj_get args `ch` )
    : s name ?? chj { T x → ( json_as_str x ) F → `` }

    ( mutex_lock . store m )
    : *DQueue q ( __dstore_get_or_create store name )
    ( mutex_unlock . store m )

    ( mutex_lock . q m )
    = . q closed 1
    ( mutex_unlock . q m )
    ^ @ !Json ClusterErr { T ( __status_env `ok` ) }
}

@ __dchan_h_len DStore store Json args → !Json ClusterErr {
    : ?Json chj ( json_obj_get args `ch` )
    : s name ?? chj { T x → ( json_as_str x ) F → `` }

    ( mutex_lock . store m )
    : *DQueue q ( __dstore_get_or_create store name )
    ( mutex_unlock . store m )

    ( mutex_lock . q m )
    : i n ( vec_len [Json] . q items )
    ( mutex_unlock . q m )
    : Json r ( json_obj_new )
    ( json_obj_set r `len` ( json_int n ) )
    ^ @ !Json ClusterErr { T r }
}

// Register the four channel handlers on a cluster Registry. The DStore is
// captured by reference (its mutex + entries Vec are shared handles).
@ dchan_register DStore store Registry r → v {
    ( registry_register r ( __wire_send )
    \ Json a → !Json ClusterErr { ^ ( __dchan_h_send store a ) } )
    ( registry_register r ( __wire_recv )
    \ Json a → !Json ClusterErr { ^ ( __dchan_h_recv store a ) } )
    ( registry_register r ( __wire_close )
    \ Json a → !Json ClusterErr { ^ ( __dchan_h_close store a ) } )
    ( registry_register r ( __wire_len )
    \ Json a → !Json ClusterErr { ^ ( __dchan_h_len store a ) } )
}

// Convenience: stand up a channel server (blocking accept loop).
@ dchan_serve s host i port DStore store → !v NetErr {
    : Registry r ( registry_new )
    ( dchan_register store r )
    : !v NetErr rr ( cluster_serve host port r )
    ( registry_free r )
    ^ rr
}

// ── Client: send outcome ─────────────────────────────────────────────

: | DSend {
    DSendOk
    DSendFull
    DSendClosed
    DSendErr  // transport failure (channel unreachable)
}

@ dsend_name DSend d → s {
    ^ ?? d {
        DSendOk → `DSendOk`
        DSendFull → `DSendFull`
        DSendClosed → `DSendClosed`
        DSendErr → `DSendErr`
    }
}

// ── Client: the generic handle ───────────────────────────────────────

: DChannelImpl [A] {
    Node node
    String name
    RetryPolicy pol
    i poll_ms
    ( @ Json A ) enc
    ( @ A Json ) dec
    ( @ v A ) drop
}

: DChannel [A] { s ctl }

@ dchan_open [A] Node node s name RetryPolicy pol i poll_ms
( @ Json A ) enc ( @ A Json ) dec ( @ v A ) drop → ( DChannel A ) {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) ( nurl_alloc Z ( DChannelImpl A ) )
    = . impl node node
    = . impl name ( string_from name )
    = . impl pol pol
    = . impl poll_ms ? > poll_ms 0 poll_ms 20
    = . impl enc enc
    = . impl dec dec
    = . impl drop drop
    ^ @ ( DChannel A ) { # s impl }
}

// Identity codecs for A = Json (the wire's native type).
@ dchan_open_json Node node s name RetryPolicy pol i poll_ms → ( DChannel Json ) {
    ^ ( dchan_open [Json] node name pol poll_ms
    \ Json v → Json { ^ ( json_clone v ) }
    \ Json j → Json { ^ ( json_clone j ) }
    \ Json j → v { ( json_free j ) } )
}

@ dchan_free [A] ( DChannel A ) ch → v {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    ( node_free . impl node )
    ( string_free . impl name )
    : ( @ Json A ) e . impl enc
    ( nurl_free # s # *u e 1 )
    : ( @ A Json ) d . impl dec
    ( nurl_free # s # *u d 1 )
    : ( @ v A ) dr . impl drop
    ( nurl_free # s # *u dr 1 )
    ( nurl_free . ch ctl )
}

@ __poll_grow i w → i {
    : i n * w 2
    ? > n 250 { ^ 250 } {}
    ^ n
}

// Build the {ch, v} args for a send. `payload` is BORROWED (cloned in).
@ __send_args s name Json payload → Json {
    : Json a ( json_obj_new )
    ( json_obj_set a `ch` ( json_str_lit name ) )
    ( json_obj_set a `v` ( json_clone payload ) )
    ^ a
}

@ __name_args s name → Json {
    : Json a ( json_obj_new )
    ( json_obj_set a `ch` ( json_str_lit name ) )
    ^ a
}

// Read the `status` string out of a borrowed response envelope.
@ __res_status Json res → s {
    : ?Json sj ( json_obj_get res `status` )
    ^ ?? sj { T x → ( json_as_str x ) F → `` }
}

// One send RPC. Returns a DSend; never consumes the caller's value.
@ __send_once [A] * ( DChannelImpl A ) impl Json payload → DSend {
    : Json args ( __send_args ( string_data . impl name ) payload )
    : !Json ClusterErr rr ( call_remote_with . impl node ( __wire_send ) args . impl pol )
    ^ ?? rr {
        T res → {
            : s st ( __res_status res )
            : DSend d ? != 0 ( nurl_str_eq st `ok` ) { @ DSend { DSendOk } } {
                ? != 0 ( nurl_str_eq st `closed` ) { @ DSend { DSendClosed } } {
                    @ DSend { DSendFull }
                }
            }
            ( json_free res )
            d
        }
        F _ → @ DSend { DSendErr }
    }
}

// Blocking send with backpressure. Consumes v (drop) on success; on a
// closed channel returns F and the caller keeps v; a full remote queue
// makes us wait and retry.
@ dchan_send [A] ( DChannel A ) ch A v → b {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    : ( @ Json A ) e . impl enc
    : Json payload ( e v )  // BORROWS v

    : ~ b done F
    : ~ b ok F
    : ~ i wait . impl poll_ms
    ~ ! done {
        : DSend d ( __send_once [A] impl payload )
        ?? d {
            DSendOk → { = ok T = done T }
            DSendClosed → { = done T }
            DSendErr → { = done T }
            DSendFull → {
                ( sleep_ms wait )
                = wait ( __poll_grow wait )
            }
        }
    }
    ( json_free payload )
    ? ok {
        : ( @ v A ) dr . impl drop
        ( dr v )
    } {}
    ^ ok
}

// Non-blocking send. DSendOk consumes v; every other outcome leaves v
// with the caller.
@ dchan_try_send [A] ( DChannel A ) ch A v → DSend {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    : ( @ Json A ) e . impl enc
    : Json payload ( e v )
    : DSend d ( __send_once [A] impl payload )
    ( json_free payload )
    ?? d {
        DSendOk → {
            : ( @ v A ) dr . impl drop
            ( dr v )
        }
        _ → {}
    }
    ^ d
}

// Result of one recv RPC. `tag`: 0 empty, 1 closed, 2 ok, 3 transport
// error. `val` is a fresh owned A — the real value when tag==2, otherwise
// a placeholder the caller must drop.
: RecvOut [A] {
    i tag
    A val
}

@ __recv_once [A] * ( DChannelImpl A ) impl → ( RecvOut A ) {
    : Json args ( __name_args ( string_data . impl name ) )
    : !Json ClusterErr rr ( call_remote_with . impl node ( __wire_recv ) args . impl pol )
    : ( @ A Json ) dec . impl dec
    ^ ?? rr {
        T res → {
            : s st ( __res_status res )
            : ( RecvOut A ) out ? != 0 ( nurl_str_eq st `ok` ) {
                : ?Json vj ( json_obj_get res `v` )  // borrow
                : A val ?? vj { T x → ( dec x ) F → ( __dec_null [A] impl ) }
                @ ( RecvOut A ) { 2 val }
            } {
                : i tg ? != 0 ( nurl_str_eq st `closed` ) 1 0
                @ ( RecvOut A ) { tg ( __dec_null [A] impl ) }
            }
            ( json_free res )
            out
        }
        F _ → @ ( RecvOut A ) { 3 ( __dec_null [A] impl ) }
    }
}

// A throwaway A produced via dec(null) — placeholder for non-ok recvs and
// for initialising mutable bindings. Always paired with a drop.
@ __dec_null [A] * ( DChannelImpl A ) impl → A {
    : ( @ A Json ) dec . impl dec
    : Json n ( json_null )
    : A a ( dec n )
    ( json_free n )
    ^ a
}

// Blocking recv. None only when the remote channel is closed AND drained.
@ dchan_recv [A] ( DChannel A ) ch → ?A {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    : ( @ v A ) dr . impl drop

    : ~ b done F
    : ~ b have F
    : ~ A result ( __dec_null [A] impl )
    : ~ i wait . impl poll_ms
    ~ ! done {
        : ( RecvOut A ) ro ( __recv_once [A] impl )
        ? == . ro tag 2 {
            ( dr result )  // release the prior placeholder
            = result . ro val
            = have T
            = done T
        } {
            ( dr . ro val )  // discard placeholder
            ? == . ro tag 0 {
                ( sleep_ms wait )
                = wait ( __poll_grow wait )
            } { = done T }  // closed or transport error → give up
        }
    }
    ? have {
        ^ @ ?A { T result }
    } {}
    ( dr result )  // discard the unused placeholder
    ^ @ ?A { F # A 0 }
}

// Non-blocking recv: one shot, None on empty/closed/error.
@ dchan_try_recv [A] ( DChannel A ) ch → ?A {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    : ( @ v A ) dr . impl drop
    : ( RecvOut A ) ro ( __recv_once [A] impl )
    ? == . ro tag 2 {
        ^ @ ?A { T . ro val }
    } {}
    ( dr . ro val )
    ^ @ ?A { F # A 0 }
}

@ dchan_close [A] ( DChannel A ) ch → v {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    : Json args ( __name_args ( string_data . impl name ) )
    : !Json ClusterErr rr ( call_remote_with . impl node ( __wire_close ) args . impl pol )
    ?? rr { T res → ( json_free res ) F _ → {} }
}

@ dchan_len [A] ( DChannel A ) ch → i {
    : *( DChannelImpl A ) impl # *( DChannelImpl A ) . ch ctl
    : Json args ( __name_args ( string_data . impl name ) )
    : !Json ClusterErr rr ( call_remote_with . impl node ( __wire_len ) args . impl pol )
    ^ ?? rr {
        T res → {
            : ?Json lj ( json_obj_get res `len` )
            : i n ?? lj { T x → ( json_as_int x ) F → 0 }
            ( json_free res )
            n
        }
        F _ → 0
    }
}
