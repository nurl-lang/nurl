// packages/swarm-mcp/tests/caps_test.nu — offline tests for the HELLO
// capability byte (census.nu) and the capability-aware roster. Run from the
// package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/caps_test.nu /tmp/ct && /tmp/ct

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/ring.nu`
$ `src/census.nu`

@ pb s label b ok → v {
    ( nurl_print label ) ( nurl_print ? ok ` PASS\n` ` FAIL\n` )
}

@ mkpk i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] v # u & + seed k 255 ) = k + k 1 }
    ^ v
}

@ main → i {
    // ── HELLO caps round-trip ─────────────────────────────────────
    : ( Vec u ) pk ( mkpk 7 )
    : ( Vec u ) msg ( hello_build 42 ( role_worker ) 1 pk ( cap_gpu ) )
    : Hello h ( hello_decode msg )
    ( pb `caps rides the HELLO wire:      ` ? == . h caps ( cap_gpu ) T F )
    ( pb `id/role/want unchanged by caps: ` & & == . h id 42 == . h role ( role_worker ) == . h want 1 )
    ( pb `pubkey unchanged by caps:       ` ( bytes_eq . h pubkey pk ) )
    ( hello_free h ) ( vec_free [u] msg )

    // ── legacy frame (no trailing caps byte) decodes as caps=0 ────
    // Build a caps frame and TRUNCATE the tail — byte-identical to what a
    // pre-caps node emits.
    : ( Vec u ) legacy ( hello_build 43 ( role_worker ) 0 pk 0 )
    : ( Vec u ) trunc ( bytes_slice legacy 0 - ( vec_len [u] legacy ) 1 )
    : Hello hl ( hello_decode trunc )
    ( pb `legacy HELLO (no tail) → caps 0:` ? == . hl caps 0 T F )
    ( pb `legacy fields still decode:     ` & == . hl id 43 ( bytes_eq . hl pubkey pk ) )
    ( hello_free hl ) ( vec_free [u] legacy ) ( vec_free [u] trunc )

    // ── roster: caps recorded, counted by mask ────────────────────
    : *Ring ring ( ring_new )
    : *Roster r ( roster_new )
    : ( Vec u ) a ( mkpk 10 )
    : ( Vec u ) b ( mkpk 60 )
    : ( Vec u ) c ( mkpk 110 )
    ( roster_add r ring a 1 8 ( cap_gpu ) )
    ( roster_add r ring b 2 8 0 )
    ( roster_add r ring c 3 8 ( cap_gpu ) )
    ( pb `roster_count all members:       ` ? == ( roster_count r ) 3 T F )
    ( pb `roster_count_caps gpu = 2:      ` ? == ( roster_count_caps r ( cap_gpu ) ) 2 T F )
    // re-adding an existing member is a no-op (idempotent HELLO)
    ( roster_add r ring a 1 8 ( cap_gpu ) )
    ( pb `re-heard HELLO is idempotent:   ` & == ( roster_count r ) 3 == ( roster_count_caps r ( cap_gpu ) ) 2 )
    ( roster_free r ) ( ring_free ring )
    ( vec_free [u] a ) ( vec_free [u] b ) ( vec_free [u] c )
    ( vec_free [u] pk )
    ^ 0
}
