// sign_key_shared_threads.nu — one prepared signing key, many signers.
//
// A TLS listener prepares its key once (std/rsa.nu RsaKey, std/mldsa.nu
// MldsaKey, inside std/tls_server.nu's TlsIdent) and every worker's
// handshakes sign with that one value at the same time. The key is never
// written after it is built — each signature works in scratch of its own —
// so eight threads signing with one Arc'd key must each get exactly the
// signature a key of their own would give.
//
// RSA: PSS with a fixed salt is deterministic, so every signature the
// shared CRT key makes (with fresh exponent blinding each time) must equal
// the one the plain private exponent makes on the main thread — two
// independent paths — and verify. ML-DSA signs hedged; every signature
// must verify under the public key.
// requires: live

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/hash_sha256.nu`

@ hx s h → ( Vec u ) { ?? ( bytes_from_hex h ) { T v → v F _ → ( vec_new [u] ) } }

@ digest i k → ( Vec u ) {
    : ( Vec u ) m ( bytes_from_str `shared key message ` )
    ( vec_push [u] m # u + 48 % k 10 )
    ^ ( sha256_pure m )
}

@ main → i {
    : ( Vec u ) n ( hx `D62EC11B49E32E3A8465049579D6310596858E8260B04F3EAD3CCC9C1C86340CA19A07B457F51CDC41664DD0949FEC8607C671D668F14678F5F7B9E4757D47808579DFE908EFD5D83CF2FB77AA962DFE11F6553D65416756928A647F090C683B8E726DA56FAB571F1CA333C723D9AB01366D76CC641AF74904FB613AEF075D37` )
    : ( Vec u ) e ( hx `010001` )
    : ( Vec u ) d ( hx `A13685F175570367D65976EECFCB121103B03989171FFE35CE0D9270FAE364F010FF3047656140BCE4990D7F2F2F84C789B8ABDCD816AB95C686152CC9E667570BA763B9CA4DEC602AB001176D98684862685B21780BB657762B8EC8FB5E67F7F9A9781E76D4DB5E3BC38ADBB84C76D6811608AE0BFF8FB3E302569C036762C9` )
    : ( Vec u ) p ( hx `F68EF2816B3B3B6348C48B91F940F1EA296A903CF05B51283BD0C3A2DB055C110BBEEBB89FABC2B7BDCFEA6B08757FD5ED3D54F40B17F62BEC4A4122E508AD75` )
    : ( Vec u ) q ( hx `DE626C129AB3C0FFF7F16873FA94987EFCE9575B1A6E93D64491025D9289DF1CDE6FAE14326C6A7892CA58C58CA4DA062234AF4B2CEAD7C943B12F36F6CD2E7B` )
    : ( Vec u ) dp ( hx `B348B8B040F01E3C10C2D2967FBFA8E953DA682DD7BD1F237973517ECF727342F5DE8B7B81A79CFC8CEA6E140C5F9C684B8D6883D8B940C92995C90D7DABB4AD` )
    : ( Vec u ) dq ( hx `8BFA9FD446148793975A1949879D293025BA2B066968D91DB22324BE0993472140D2435CEB305B047241740745342F1855479C5F5172B1493A96B9057BEC4329` )
    : ( Vec u ) qi ( hx `527F8546BF7B12806CD9E060EBFCC9D19EE01C17489E981E085F89AB00C62BFBA52B28758B11A30D049EE7198F562BE32FAD8E41B1040EA3D621A8F193DB8495` )
    : ( Vec u ) salt ( hx `202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f` )

    // An even "prime" is refused when the key is prepared, not signed with.
    : ( Vec u ) even ( hx `F68EF2816B3B3B6348C48B91F940F1EA296A903CF05B51283BD0C3A2DB055C110BBEEBB89FABC2B7BDCFEA6B08757FD5ED3D54F40B17F62BEC4A4122E508AD74` )
    ( nurl_println ?? ( rsa_key_crt n e even q dp dq qi ) { T _ → `even prime: accepted` F → `even prime: refused` } )

    : RsaKey crt ?? ( rsa_key_crt n e p q dp dq qi ) {
        T k → k
        F → { ( nurl_println `CRT key refused` ) ^ 1 }
    }
    : ( Arc RsaKey ) rkey ( arc_new [RsaKey] crt )
    // The references, from the plain exponent on this thread.
    : ( Vec ( Vec u ) ) refs ( vec_new [( Vec u )] )
    : ~ i k 0
    ~ < k 10 { ( vec_push [( Vec u )] refs ( rsa_pss_sign_sha256 n e d ( digest k ) salt ) ) = k + k 1 }
    : ( Arc ( Vec ( Vec u ) ) ) rrefs ( arc_new [( Vec ( Vec u ) )] refs )

    : MldsaKeys ks ( mldsa_keygen_derand 65 ( hx `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f` ) )
    : ( Arc MldsaKey ) mkey ( arc_new [MldsaKey] ( mldsa_sign_key 65 ( mldsa_sk ks ) ) )
    : ( Arc ( Vec u ) ) mpk ( arc_new [( Vec u )] ( bytes_slice ( mldsa_pk ks ) 0 ( vec_len [u] ( mldsa_pk ks ) ) ) )

    : Atomic rsa_ok ( atomic_new 0 )
    : Atomic ml_ok ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc RsaKey ) rk ( arc_clone [RsaKey] rkey )
        : ( Arc ( Vec ( Vec u ) ) ) rr ( arc_clone [( Vec ( Vec u ) )] rrefs )
        : ( Arc MldsaKey ) mk ( arc_clone [MldsaKey] mkey )
        : ( Arc ( Vec u ) ) pk ( arc_clone [( Vec u )] mpk )
        : ( Vec u ) sl ( bytes_slice salt 0 ( vec_len [u] salt ) )
        : i base t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i j 0
            ~ < j 10 {
                : i m % + base j 10
                : ( Vec u ) dg ( digest m )
                : ( Vec u ) sg ( rsa_pss_sign_sha256_key ( arc_get [RsaKey] rk ) dg sl )
                : ( Vec u ) want ?? ( vec_get [( Vec u )] ( arc_get [( Vec ( Vec u ) )] rr ) m ) { T w → w F _ → ( vec_new [u] ) }
                : b same & ( bytes_eq sg want ) ( rsa_pss_verify_sha256 ( rsa_key_n ( arc_get [RsaKey] rk ) ) ( rsa_key_e ( arc_get [RsaKey] rk ) ) sg dg )
                ? same { ( atomic_add rsa_ok 1 ) } {}
                ? < j 2 {
                    : ( Vec u ) ctx ( vec_new [u] )
                    : ( Vec u ) ms ( mldsa_sign_with ( arc_get [MldsaKey] mk ) dg ctx )
                    ? ( mldsa_verify 65 ( arc_get [( Vec u )] pk ) dg ctx ms ) { ( atomic_add ml_ok 1 ) } {}
                } {}
                = j + j 1
            }
        } )
        ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → { ( nurl_println `spawn failed` ) } }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( nurl_print `RSA signatures equal to the plain key's and verified: ` ) ( nurl_println_int ( atomic_load rsa_ok ) )
    ( nurl_print `ML-DSA signatures verified: ` ) ( nurl_println_int ( atomic_load ml_ok ) )
    ^ 0
}
