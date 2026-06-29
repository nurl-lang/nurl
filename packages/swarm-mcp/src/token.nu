// packages/swarm-mcp/src/token.nu — cluster identity + authenticity from one
// shared `--token`.
//
// Every node in a cluster is launched with the same `--token`. The token does
// two things, both derived deterministically so no node has to coordinate:
//
//   1. ISOLATION — `token_group_id` hashes the token into the 32-byte relay
//      multicast group id. Clusters with different tokens join different relay
//      groups, so their HELLO/job traffic is mutually invisible even when they
//      share one relay. Without the token you cannot derive the group id, so a
//      stranger cannot even see (let alone join) the cluster's gossip.
//
//   2. AUTHENTICITY — `token_key` derives a 32-byte HMAC key. Every compute
//      payload (a kernel chunk) and every result is tagged with HMAC-SHA256
//      (`token_tag`) and verified on receipt (`token_untag`, constant-time).
//      A worker only acts on token-authentic jobs; a coordinator only accepts
//      token-authentic results. Combined with group isolation this gives mutual
//      authentication of all compute traffic over the dumb (opaque) relay.
//
// The relay itself never needs the token — it forwards opaque bytes — so the
// secret never leaves the nodes that own it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/subtle.nu`

// HMAC tag length prepended to authenticated messages (truncated SHA-256 MAC).
@ token_tag_len → i { ^ 16 }

// Domain-separated SHA-256 over (label ++ token) → 32 bytes. The label keeps
// the group id and the HMAC key independent even though both come from the
// same token.
@ __token_derive s label s token → ( Vec u ) {
    : ( Vec u ) m ( bytes_from_str label )
    : ( Vec u ) tb ( bytes_from_str token )
    ( bytes_extend_bytes m tb )
    ( vec_free [u] tb )
    : ( Vec u ) h ( sha256_pure m )
    ( vec_free [u] m )
    ^ h
}

// 32-byte relay multicast group id for this cluster (token isolation).
@ token_group_id s token → ( Vec u ) { ^ ( __token_derive `swarm-mcp/group/v1:` token ) }

// 32-byte HMAC key authenticating compute payloads + results.
@ token_key s token → ( Vec u ) { ^ ( __token_derive `swarm-mcp/hmac/v1:` token ) }

// Prepend a 16-byte HMAC-SHA256 tag to `payload`. Returns a NEW vec; the caller
// owns it (and still owns `payload`).
@ token_tag ( Vec u ) key ( Vec u ) payload → ( Vec u ) {
    : i tl ( token_tag_len )
    : ( Vec u ) mac ( hmac_sha256_pure key payload )
    : ( Vec u ) out ( vec_with_cap [u] + tl ( vec_len [u] payload ) )
    : ~ i k 0
    ~ < k tl { ?? ( vec_get [u] mac k ) { T x → ( vec_push [u] out x ) F → {} } = k + k 1 }
    ( vec_extend [u] out payload )
    ( vec_free [u] mac )
    ^ out
}

// Verify the tag and strip it. Some(payload copy) on a valid tag, None on a
// missing/short/forged tag. The compare is constant-time. Caller owns the
// returned payload on the Some arm.
@ token_untag ( Vec u ) key ( Vec u ) tagged → ?( Vec u ) {
    : i tl ( token_tag_len )
    : i n ( vec_len [u] tagged )
    ? < n tl { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ( Vec u ) tag ( bytes_slice tagged 0 tl )
    : ( Vec u ) payload ( bytes_slice tagged tl n )
    : ( Vec u ) mac_full ( hmac_sha256_pure key payload )
    : ( Vec u ) mac ( bytes_slice mac_full 0 tl )
    ( vec_free [u] mac_full )
    : b ok ( constant_time_eq_vec tag mac )
    ( vec_free [u] tag ) ( vec_free [u] mac )
    ? ok { ^ @ ?( Vec u ) { T payload } } {}
    ( vec_free [u] payload )
    ^ @ ?( Vec u ) { F # ( Vec u ) 0 }
}
