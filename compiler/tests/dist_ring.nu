// dist_ring.nu — offline test for stdlib/dist/ring.nu. Deterministic: builds
// a consistent-hash ring of 3 members (64 vnodes each), checks ownership is
// well-defined + stable, load is spread across all members, replica sets are
// distinct, and — the consistent-hashing property — removing a member only
// re-homes the keys it owned.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/ring.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }
@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}
// distinct key bytes per i (4-byte LE)
@ mkkey i x → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 24 255 )
    ^ v
}
@ owner_seed *Ring r ( Vec u ) key ( Vec u ) a ( Vec u ) b ( Vec u ) c → i {
    ^ ?? ( ring_owner_pk r key ) {
        T pk → { : i s ? ( veq pk a ) 1 ? ( veq pk b ) 2 ? ( veq pk c ) 3 0 ( vec_free [u] pk ) s }
        F → 0
    }
}

@ main → i {
    : ( Vec u ) a ( mkpk 10 )
    : ( Vec u ) b ( mkpk 80 )
    : ( Vec u ) c ( mkpk 150 )

    : *Ring r ( ring_new )
    ( ring_add_member r a 64 )
    ( ring_add_member r b 64 )
    ( ring_add_member r c 64 )
    ( pb `ring has 192 points (3 x 64): ` == ( ring_point_count r ) 192 )

    // ownership well-defined + deterministic
    : ( Vec u ) k0 ( mkkey 12345 )
    : i o1 ( owner_seed r k0 a b c )
    : i o2 ( owner_seed r k0 a b c )
    ( pb `key has a valid owner: ` > o1 0 )
    ( pb `ownership deterministic: ` == o1 o2 )
    ( vec_free [u] k0 )

    // load spread: across 300 keys every member owns some, none orphaned
    : ~ i ca 0 : ~ i cb 0 : ~ i cc 0 : ~ i bad 0
    : ~ i i 0
    ~ < i 300 {
        : ( Vec u ) key ( mkkey * i 2654435761 )
        : i s ( owner_seed r key a b c )
        ? == s 1 { = ca + ca 1 } { ? == s 2 { = cb + cb 1 } { ? == s 3 { = cc + cc 1 } { = bad + bad 1 } } }
        ( vec_free [u] key )
        = i + i 1
    }
    ( pb `no key unowned: ` == bad 0 )
    ( pb `all 3 members carry load: ` & & > ca 0 > cb 0 > cc 0 )
    ( pb `total accounted: ` == + + ca cb cc 300 )

    // replica set: 2 distinct owners
    : ( Vec u ) rk ( mkkey 999983 )
    : ( Vec s ) reps ( ring_owners r rk 2 )
    ( pb `replica set size 2: ` == ( vec_len [s] reps ) 2 )
    : s r0 ?? ( vec_get [s] reps 0 ) { T x → x F → # s 0 }
    : s r1 ?? ( vec_get [s] reps 1 ) { T x → x F → # s 0 }
    : *RingPoint rp0 # *RingPoint r0
    : *RingPoint rp1 # *RingPoint r1
    ( pb `replicas distinct: ` ! ( veq . rp0 owner . rp1 owner ) )
    ( vec_free [s] reps )
    ( vec_free [u] rk )

    // consistent hashing: removing C only re-homes C's keys
    : ~ i stable 0 : ~ i remapped 0 : ~ i was_c 0
    // snapshot owners, then remove c, re-check
    ( ring_remove_member r c )
    ( pb `ring now 128 points: ` == ( ring_point_count r ) 128 )
    : ~ i j 0
    ~ < j 300 {
        : ( Vec u ) key ( mkkey * j 2654435761 )
        : i after ( owner_seed r key a b c )
        // recompute what it WAS by rebuilding owner on a fresh 3-node ring
        ( vec_free [u] key )
        = j + j 1
    }
    // rebuild a reference 3-node ring to compare pre/post removal
    : *Ring ref ( ring_new )
    ( ring_add_member ref a 64 ) ( ring_add_member ref b 64 ) ( ring_add_member ref c 64 )
    : ~ i m 0
    ~ < m 300 {
        : ( Vec u ) key ( mkkey * m 2654435761 )
        : i before ( owner_seed ref key a b c )
        : i after ( owner_seed r key a b c )
        ? == before 3 { = was_c + was_c 1 }
        { ? == before after { = stable + stable 1 } { = remapped + remapped 1 } }
        ( vec_free [u] key )
        = m + m 1
    }
    ( pb `non-C keys kept their owner after C left: ` == remapped 0 )
    ( pb `some keys were owned by C (and re-homed): ` > was_c 0 )
    ( pb `stable + was_c == 300: ` == + stable was_c 300 )
    ( ring_free ref )

    ( ring_free r )
    ( vec_free [u] a ) ( vec_free [u] b ) ( vec_free [u] c )
    ^ 0
}
