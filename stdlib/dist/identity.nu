// stdlib/dist/identity.nu — stable replica identity (§7.5 Phase 9.1).
//
// dist/crdt replicas are keyed by a small integer id. If those ids are handed
// out naively (e.g. "position in the member list") then churn SILENTLY
// corrupts state: a departed node's id gets reused by a new pubkey, and that
// new node inherits the retired node's PNCounter slot or its OR-Set
// `(replica, seq)` tag space. The merge stays mathematically valid but the
// VALUES are wrong, with no error anywhere.
//
// This registry removes that hazard. It maps each peer's static public key to
// a MONOTONIC, NEVER-REUSED replica id:
//
//   * a pubkey seen for the first time gets the next id (a high-water mark
//     that only ever increases);
//   * the same pubkey across leave → rejoin resolves to the SAME id (it
//     resumes its own slot);
//   * a new pubkey NEVER inherits a retired id.
//
// Retired ids are tombstoned (kept, marked not-live) so stale gossip that
// still references a dead replica can be interpreted, and so a rejoin revives
// the original binding. Feed `dist/crdt.nu` / `dist/replicator.nu` from
// `identity_of(pubkey)` instead of raw caller-assigned ints.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __id_veq ( Vec u ) a ( Vec u ) b → b {
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
@ __id_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

: IdEntry {
    ( Vec u ) pubkey
    i id
    i live       // 1 = active, 0 = retired (tombstone; id still bound here)
}

: IdRegistry {
    ( Vec s ) entries   // *IdEntry
    i next_id           // monotonic high-water mark — never decreases
}

@ identity_new → *IdRegistry {
    : *IdRegistry r # *IdRegistry ( nurl_alloc Z IdRegistry )
    = . r entries ( vec_new [s] )
    = . r next_id 0
    ^ r
}

@ identity_free *IdRegistry r → v {
    : i n ( vec_len [s] . r entries )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r entries k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *IdEntry e # *IdEntry pp ( vec_free [u] . e pubkey ) ( nurl_free # s e ) } {}
        = k + k 1
    }
    ( vec_free [s] . r entries )
    ( nurl_free # s r )
}

@ identity_count *IdRegistry r → i { ^ ( vec_len [s] . r entries ) }

@ __id_find *IdRegistry r ( Vec u ) pubkey → s {
    : i n ( vec_len [s] . r entries )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . r entries k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *IdEntry e # *IdEntry pp
            ? ( __id_veq . e pubkey pubkey ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// The stable replica id for a pubkey. Allocates the next id on first sight;
// a known pubkey (even a retired one) returns its existing id and is marked
// live again (a rejoin resumes its own slot). A new pubkey never reuses a
// retired id — next_id only grows.
@ identity_of *IdRegistry r ( Vec u ) pubkey → i {
    : s pp ( __id_find r pubkey )
    ? != # i pp 0 {
        : *IdEntry e # *IdEntry pp
        = . e live 1
        ^ . e id
    } {}
    : *IdEntry e # *IdEntry ( nurl_alloc Z IdEntry )
    = . e pubkey ( __id_cpy pubkey )
    = . e id . r next_id
    = . e live 1
    = . r next_id + . r next_id 1
    ( vec_push [s] . r entries # s e )
    ^ . e id
}

// Has this pubkey ever been assigned an id (without allocating one)?
@ identity_known *IdRegistry r ( Vec u ) pubkey → b { ^ != # i ( __id_find r pubkey ) 0 }

// Reverse lookup: the pubkey bound to a replica id (copied), or None. Resolves
// retired (tombstoned) ids too, so stale gossip remains interpretable.
@ identity_pubkey *IdRegistry r i id → ?( Vec u ) {
    : i n ( vec_len [s] . r entries )
    : ~ ?( Vec u ) out @ ?( Vec u ) { F # ( Vec u ) 0 }
    : ~ b got F
    : ~ i k 0
    ~ & ! got < k n {
        : s pp ?? ( vec_get [s] . r entries k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *IdEntry e # *IdEntry pp
            ? == . e id id { = out @ ?( Vec u ) { T ( __id_cpy . e pubkey ) } = got T } {}
        } {}
        = k + k 1
    }
    ^ out
}

// Retire a pubkey's slot (it left). The binding is kept as a tombstone — the
// id is never reassigned, and a later identity_of on the same pubkey revives
// it. No-op for an unknown pubkey.
@ identity_retire *IdRegistry r ( Vec u ) pubkey → v {
    : s pp ( __id_find r pubkey )
    ? != # i pp 0 { : *IdEntry e # *IdEntry pp = . e live 0 } {}
}

// Is the id currently live (not retired)? Unknown ids report not-live.
@ identity_is_live *IdRegistry r i id → b {
    : i n ( vec_len [s] . r entries )
    : ~ b live F : ~ i k 0
    ~ & ! live < k n {
        : s pp ?? ( vec_get [s] . r entries k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *IdEntry e # *IdEntry pp ? & == . e id id == . e live 1 { = live T } {} } {}
        = k + k 1
    }
    ^ live
}
