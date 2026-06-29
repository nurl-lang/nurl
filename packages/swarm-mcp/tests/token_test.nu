// packages/swarm-mcp/tests/token_test.nu — offline tests for the cluster token:
// group-id isolation and HMAC payload authenticity. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/token_test.nu /tmp/tt && /tmp/tt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/token.nu`

@ pb s label b ok → v {
    ( nurl_print label ) ( nurl_print ? ok ` PASS\n` ` FAIL\n` )
}

@ main → i {
    // group id: deterministic, 32 bytes, isolates by token
    : ( Vec u ) g1 ( token_group_id `alpha` )
    : ( Vec u ) g1b ( token_group_id `alpha` )
    : ( Vec u ) g2 ( token_group_id `beta` )
    ( pb `group id is 32 bytes:        ` ? == ( vec_len [u] g1 ) 32 T F )
    ( pb `same token → same group:     ` ( bytes_eq g1 g1b ) )
    ( pb `diff token → diff group:     ` ? ( bytes_eq g1 g2 ) F T )

    // HMAC tag round-trips for the right key
    : ( Vec u ) key ( token_key `alpha` )
    : ( Vec u ) wrong ( token_key `beta` )
    : ( Vec u ) msg ( bytes_from_str `op-lo-hi-expr payload` )
    : ( Vec u ) tagged ( token_tag key msg )
    ( pb `tag adds 16-byte prefix:      ` ? == ( vec_len [u] tagged ) + 16 ( vec_len [u] msg ) T F )
    : ~ b ok_rt F
    ?? ( token_untag key tagged ) { T body → { = ok_rt ( bytes_eq body msg ) ( vec_free [u] body ) } F → {} }
    ( pb `valid tag verifies + strips:  ` ok_rt )

    // wrong key is rejected
    : ~ b rej_wrong T
    ?? ( token_untag wrong tagged ) { T body → { = rej_wrong F ( vec_free [u] body ) } F → {} }
    ( pb `wrong key rejected:           ` rej_wrong )

    // a flipped byte is rejected (forgery / corruption)
    : ( Vec u ) forged ( token_tag key msg )
    ?? ( vec_get [u] forged 20 ) { T b → ( vec_set [u] forged 20 # u ^^ b 255 ) F → {} }
    : ~ b rej_forge T
    ?? ( token_untag key forged ) { T body → { = rej_forge F ( vec_free [u] body ) } F → {} }
    ( pb `forged payload rejected:      ` rej_forge )

    // too-short input is rejected
    : ( Vec u ) tiny ( bytes_from_str `xx` )
    : ~ b rej_short T
    ?? ( token_untag key tiny ) { T body → { = rej_short F ( vec_free [u] body ) } F → {} }
    ( pb `short input rejected:         ` rej_short )

    ( vec_free [u] g1 ) ( vec_free [u] g1b ) ( vec_free [u] g2 )
    ( vec_free [u] key ) ( vec_free [u] wrong ) ( vec_free [u] msg )
    ( vec_free [u] tagged ) ( vec_free [u] forged ) ( vec_free [u] tiny )
    ^ 0
}
