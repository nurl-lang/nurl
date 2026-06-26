// stdlib/std/rsa.nu — pure-NURL RSA signatures (RSASSA PKCS#1 v1.5 and
// PSS), built on the BigInt modular exponentiation. No OpenSSL. Verify
// (X.509 / TLS 1.3 cert signatures) plus PSS signing (the pure TLS 1.3
// server's CertificateVerify with an RSA leaf cert).
//
//   ( rsa_pkcs1_verify n e sig di_prefix digest ) → b
//   ( rsa_pss_verify_sha256 n e sig mhash )        → b
//   ( rsa_pss_sign_sha256 n d mhash salt )         → sig  (k-byte BE)
//
// n / e / sig are big-endian byte vectors (the modulus, public exponent,
// and signature). `digest` is the raw hash of the signed data; di_prefix
// is the DigestInfo ASN.1 prefix for that hash (see the rsa_di_* helpers).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/hash_sha256.nu`

// OS CSPRNG bridge (same runtime entry std/random.nu uses) — for the RSA
// blinding nonce. Returns 1 on success, 0 on total entropy failure.
& `c` @ nurl_rand_fill *u buf i n → i

@ __rsa_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ -1 }
}

// A fresh random BigInt in [0, n) for blinding: fill `k` bytes from the OS
// CSPRNG and reduce mod n. (Whole-modulus width so the reduction is ~uniform.)
@ __rsa_rand_mod BigInt bn i k → BigInt {
    : ( Vec u ) buf ( vec_with_cap [u] ? > k 0 k 1 )
    : ~ i z 0
    ~ < z k { ( vec_push [u] buf # u 0 ) = z + z 1 }
    : i r ( nurl_rand_fill # *u ( vec_data [u] buf ) k )
    ? == r 0 { ( nurl_panic `rsa: CSPRNG (nurl_rand_fill) failed` ) } {}
    : BigInt rb ( bigint_from_bytes_be buf )
    : BigInt rm ( bigint_rem rb bn )
    ( vec_free [u] buf ) ( bigint_free rb )
    ^ rm
}

// L1: a well-formed signature representative is exactly k bytes and < n.
// Rejecting otherwise removes the sig / sig+n malleability (RFC 8017 §8).
@ __rsa_sig_inrange ( Vec u ) n ( Vec u ) sig → b {
    ? != ( vec_len [u] sig ) ( vec_len [u] n ) { ^ F } {}
    : BigInt bn ( bigint_from_bytes_be n )
    : BigInt bs ( bigint_from_bytes_be sig )
    : b ok < ( bigint_cmp bs bn ) 0
    ( bigint_free bn ) ( bigint_free bs )
    ^ ok
}

// Recover the encoded message EM = sig^e mod n, padded to the modulus
// length (k bytes).
@ __rsa_em ( Vec u ) n ( Vec u ) e ( Vec u ) sig → ( Vec u ) {
    : BigInt bn ( bigint_from_bytes_be n )
    : BigInt be ( bigint_from_bytes_be e )
    : BigInt bs ( bigint_from_bytes_be sig )
    : BigInt m ( bigint_modpow bs be bn )
    : ( Vec u ) em ( bigint_to_bytes_be m ( vec_len [u] n ) )
    ( bigint_free bn )
    ( bigint_free be )
    ( bigint_free bs )
    ( bigint_free m )
    ^ em
}

// DigestInfo ASN.1 prefixes (RFC 8017 §9.2 notes).
@ rsa_di_sha256 → ( Vec u ) {
    ^ ?? ( bytes_from_hex `3031300d060960864801650304020105000420` ) { T v → v F _ → ( vec_new [u] ) }
}

@ rsa_di_sha384 → ( Vec u ) {
    ^ ?? ( bytes_from_hex `3041300d060960864801650304020205000430` ) { T v → v F _ → ( vec_new [u] ) }
}

@ rsa_di_sha512 → ( Vec u ) {
    ^ ?? ( bytes_from_hex `3051300d060960864801650304020305000440` ) { T v → v F _ → ( vec_new [u] ) }
}

// RSASSA-PKCS1-v1.5 verify. EM must be 0x00 0x01 [0xFF…] 0x00 || T,
// where T = di_prefix || digest (RFC 8017 §9.2). Constant work over the
// recovered EM; the comparison is structural, not secret-dependent.
@ rsa_pkcs1_verify ( Vec u ) n ( Vec u ) e ( Vec u ) sig ( Vec u ) di_prefix ( Vec u ) digest → b {
    : i k ( vec_len [u] n )
    ? < k 11 { ^ F } {}
    ? ! ( __rsa_sig_inrange n sig ) { ^ F } {}
    : ( Vec u ) em ( __rsa_em n e sig )
    : i tlen + ( vec_len [u] di_prefix ) ( vec_len [u] digest )
    // PS length = k - tlen - 3, must be >= 8
    : i pslen - - - k tlen 3 0
    : ~ b ok T
    ? < pslen 8 { = ok F } {}
    ? != ( __rsa_bget em 0 ) 0 { = ok F } {}
    ? != ( __rsa_bget em 1 ) 1 { = ok F } {}
    : ~ i i 2
    : i psend + 2 pslen
    ~ < i psend { ? != ( __rsa_bget em i ) 255 { = ok F } {} = i + i 1 }
    ? != ( __rsa_bget em psend ) 0 { = ok F } {}
    : i tstart + psend 1
    : i dplen ( vec_len [u] di_prefix )
    : ~ i j 0
    ~ < j dplen {
        ? != ( __rsa_bget em + tstart j ) ( __rsa_bget di_prefix j ) { = ok F } {}
        = j + j 1
    }
    : i dlen ( vec_len [u] digest )
    : ~ i d 0
    ~ < d dlen {
        ? != ( __rsa_bget em + + tstart dplen d ) ( __rsa_bget digest d ) { = ok F } {}
        = d + d 1
    }
    ( vec_free [u] em )
    ^ ok
}

// Convenience for the common SHA-256 case.
@ rsa_pkcs1_verify_sha256 ( Vec u ) n ( Vec u ) e ( Vec u ) sig ( Vec u ) digest → b {
    : ( Vec u ) di ( rsa_di_sha256 )
    : b r ( rsa_pkcs1_verify n e sig di digest )
    ( vec_free [u] di )
    ^ r
}

// ── RSASSA-PSS verify (MGF1-SHA-256, salt length = hash length) ───
// This is the RSA signature scheme TLS 1.3 mandates for RSA certs in
// CertificateVerify (rsa_pss_rsae_sha256) and many CAs use for chains.

// MGF1 with SHA-256: stretch `seed` to `len` bytes.
@ __mgf1_sha256 ( Vec u ) seed i len → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] ? > len 0 len 1 )
    : ~ i counter 0
    ~ < ( vec_len [u] out ) len {
        : ( Vec u ) inb ( vec_with_cap [u] + ( vec_len [u] seed ) 4 )
        : ~ i si 0
        ~ < si ( vec_len [u] seed ) { ( vec_push [u] inb # u ( __rsa_bget seed si ) ) = si + si 1 }
        ( vec_push [u] inb # u & >> counter 24 255 )
        ( vec_push [u] inb # u & >> counter 16 255 )
        ( vec_push [u] inb # u & >> counter 8 255 )
        ( vec_push [u] inb # u & counter 255 )
        : ( Vec u ) blk ( sha256_pure inb )
        : ~ i bi 0
        ~ & < bi 32 < ( vec_len [u] out ) len { ( vec_push [u] out # u ( __rsa_bget blk bi ) ) = bi + bi 1 }
        ( vec_free [u] inb )
        ( vec_free [u] blk )
        = counter + counter 1
    }
    ^ out
}

// Bit length of a big-endian magnitude (for emBits = modBits - 1).
@ __rsa_bitlen ( Vec u ) n → i {
    : i len ( vec_len [u] n )
    : ~ i i 0
    ~ & < i len == ( __rsa_bget n i ) 0 { = i + i 1 }
    ? >= i len { ^ 0 } {}
    : i top ( __rsa_bget n i )
    : ~ i bits * 8 - - len i 1
    : ~ i t top
    : ~ i extra 0
    ~ > t 0 { = extra + extra 1 = t >> t 1 }
    ^ + bits extra
}

// RSASSA-PSS-VERIFY with SHA-256 and salt length = 32 (RFC 8017 §9.1.2,
// specialised to the TLS 1.3 rsa_pss_rsae_sha256 parameters). `mhash` is
// SHA-256 of the signed data.
@ rsa_pss_verify_sha256 ( Vec u ) n ( Vec u ) e ( Vec u ) sig ( Vec u ) mhash → b {
    : i hlen 32
    : i slen 32
    : i k ( vec_len [u] n )
    : i embits - ( __rsa_bitlen n ) 1
    : i emlen / + embits 7 8
    ? < emlen + + hlen slen 2 { ^ F } {}
    ? ! ( __rsa_sig_inrange n sig ) { ^ F } {}
    : ( Vec u ) emfull ( __rsa_em n e sig )
    // emfull is k bytes; EM is its low emLen bytes (right-aligned).
    : ( Vec u ) em ( bytes_slice emfull - k emlen k )
    ( vec_free [u] emfull )
    : ~ b ok T
    ? != ( __rsa_bget em - emlen 1 ) 188 { = ok F } {}  // trailer 0xbc
    : i dblen - - emlen hlen 1
    : ( Vec u ) maskeddb ( bytes_slice em 0 dblen )
    // L2 (RFC 8017 §9.1.2 step 5): the leftmost (8·emLen − emBits) bits of
    // maskedDB MUST be zero — reject non-canonical encodings.
    : i __clr - * 8 emlen embits
    : i __m0 & >> 255 __clr 255
    : i __topmask & 255 ^^ 255 __m0
    ? != 0 & ( __rsa_bget maskeddb 0 ) __topmask { = ok F } {}
    : ( Vec u ) h ( bytes_slice em dblen + dblen hlen )
    : ( Vec u ) dbmask ( __mgf1_sha256 h dblen )
    : ( Vec u ) db ( vec_with_cap [u] dblen )
    : ~ i i 0
    ~ < i dblen { ( vec_push [u] db # u ^^ ( __rsa_bget maskeddb i ) ( __rsa_bget dbmask i ) ) = i + i 1 }
    // Clear the leftmost (8*emLen - emBits) bits of DB[0].
    : i clearbits - * 8 emlen embits
    : i mask0 & >> 255 clearbits 255
    ( vec_set [u] db 0 # u & ( __rsa_bget db 0 ) mask0 )
    // DB must be 0x00.. 0x01 || salt.
    : i psend - - dblen slen 1
    : ~ i p 0
    ~ < p psend { ? != ( __rsa_bget db p ) 0 { = ok F } {} = p + p 1 }
    ? != ( __rsa_bget db psend ) 1 { = ok F } {}
    : ( Vec u ) salt ( bytes_slice db + psend 1 dblen )
    // H' = SHA-256( 0x00*8 || mHash || salt ).
    : ( Vec u ) mprime ( vec_with_cap [u] + + 8 hlen slen )
    : ~ i z 0
    ~ < z 8 { ( vec_push [u] mprime # u 0 ) = z + z 1 }
    : ~ i mi 0
    ~ < mi hlen { ( vec_push [u] mprime # u ( __rsa_bget mhash mi ) ) = mi + mi 1 }
    : ~ i sj 0
    ~ < sj ( vec_len [u] salt ) { ( vec_push [u] mprime # u ( __rsa_bget salt sj ) ) = sj + sj 1 }
    : ( Vec u ) hprime ( sha256_pure mprime )
    : ~ i c 0
    ~ < c hlen { ? != ( __rsa_bget hprime c ) ( __rsa_bget h c ) { = ok F } {} = c + c 1 }
    ( vec_free [u] em ) ( vec_free [u] maskeddb ) ( vec_free [u] h ) ( vec_free [u] dbmask )
    ( vec_free [u] db ) ( vec_free [u] salt ) ( vec_free [u] mprime ) ( vec_free [u] hprime )
    ^ ok
}

// RSASSA-PSS-SIGN with SHA-256 (RFC 8017 §8.1.1 + §9.1.1), specialised to
// the TLS 1.3 rsa_pss_rsae_sha256 parameters (MGF1-SHA-256, salt length =
// hash length). `n`/`e`/`d` are the modulus, PUBLIC exponent and PRIVATE
// exponent (big-endian); `mhash` is SHA-256 of the signed data; `salt` is
// the random salt (32 bytes for TLS 1.3) — passed in so the caller owns the
// RNG and tests can pin it. Returns the k-byte big-endian signature.
//
// H1 (base blinding): the private-key exponentiation s = EM^d mod n is
// computed as s = ((EM · r^e)^d · r^{-1}) mod n for a fresh random r per
// signature. r^{ed} ≡ r mod n, so this unblinds to the same signature, but
// the value actually fed to the (variable-time) modexp is randomized, so its
// timing no longer correlates with EM or d — defeating remote/cache timing
// recovery of the key (the standard OpenSSL defense). `e` is public.
@ rsa_pss_sign_sha256 ( Vec u ) n ( Vec u ) e ( Vec u ) d ( Vec u ) mhash ( Vec u ) salt → ( Vec u ) {
    : i hlen 32
    : i slen ( vec_len [u] salt )
    : i k ( vec_len [u] n )
    : i embits - ( __rsa_bitlen n ) 1
    : i emlen / + embits 7 8
    // M' = 0x00*8 || mHash || salt ;  H = SHA-256(M')
    : ( Vec u ) mprime ( vec_with_cap [u] + + 8 hlen slen )
    : ~ i z 0
    ~ < z 8 { ( vec_push [u] mprime # u 0 ) = z + z 1 }
    : ~ i mi 0
    ~ < mi hlen { ( vec_push [u] mprime # u ( __rsa_bget mhash mi ) ) = mi + mi 1 }
    : ~ i sj 0
    ~ < sj slen { ( vec_push [u] mprime # u ( __rsa_bget salt sj ) ) = sj + sj 1 }
    : ( Vec u ) h ( sha256_pure mprime )
    // DB = PS(0x00…) || 0x01 || salt ;  len = emLen - hLen - 1
    : i dblen - - emlen hlen 1
    : i psend - - dblen slen 1
    : ( Vec u ) db ( vec_with_cap [u] dblen )
    : ~ i pi 0
    ~ < pi psend { ( vec_push [u] db # u 0 ) = pi + pi 1 }
    ( vec_push [u] db # u 1 )
    : ~ i si 0
    ~ < si slen { ( vec_push [u] db # u ( __rsa_bget salt si ) ) = si + si 1 }
    // maskedDB = DB XOR MGF1(H, dbLen) ; then EM = maskedDB || H || 0xbc
    : ( Vec u ) dbmask ( __mgf1_sha256 h dblen )
    : ( Vec u ) em ( vec_with_cap [u] emlen )
    : ~ i di 0
    ~ < di dblen { ( vec_push [u] em # u ^^ ( __rsa_bget db di ) ( __rsa_bget dbmask di ) ) = di + di 1 }
    // Clear the leftmost (8*emLen - emBits) bits of maskedDB[0].
    : i clearbits - * 8 emlen embits
    : i mask0 & >> 255 clearbits 255
    ( vec_set [u] em 0 # u & ( __rsa_bget em 0 ) mask0 )
    : ~ i hi 0
    ~ < hi hlen { ( vec_push [u] em # u ( __rsa_bget h hi ) ) = hi + hi 1 }
    ( vec_push [u] em # u 188 )  // trailer 0xbc
    // s = EM^d mod n, with base blinding, encoded big-endian to k bytes.
    : BigInt bm ( bigint_from_bytes_be em )
    : BigInt bd ( bigint_from_bytes_be d )
    : BigInt be ( bigint_from_bytes_be e )
    : BigInt bn ( bigint_from_bytes_be n )
    : BigInt r ( __rsa_rand_mod bn k )
    : BigInt rinv ( bigint_modinv r bn )
    : ~ BigInt bsig ( bigint_zero )
    ? ( bigint_is_zero rinv ) {
        // r not invertible (astronomically rare for n=pq) → sign unblinded.
        ( bigint_free bsig )
        = bsig ( bigint_modpow bm bd bn )
    } {
        : BigInt re ( bigint_modpow r be bn )       // r^e mod n (public exp, fast)
        : BigInt mb ( bigint_mul bm re )
        : BigInt mbr ( bigint_rem mb bn )           // EM·r^e mod n
        : BigInt sb ( bigint_modpow mbr bd bn )     // (EM·r^e)^d = EM^d·r mod n
        : BigInt su ( bigint_mul sb rinv )
        ( bigint_free bsig )
        = bsig ( bigint_rem su bn )                 // ·r^{-1} → EM^d mod n
        ( bigint_free re ) ( bigint_free mb ) ( bigint_free mbr )
        ( bigint_free sb ) ( bigint_free su )
    }
    : ( Vec u ) sig ( bigint_to_bytes_be bsig k )
    ( bigint_free bm ) ( bigint_free bd ) ( bigint_free be ) ( bigint_free bn )
    ( bigint_free r ) ( bigint_free rinv ) ( bigint_free bsig )
    ( vec_free [u] mprime ) ( vec_free [u] h ) ( vec_free [u] db )
    ( vec_free [u] dbmask ) ( vec_free [u] em )
    ^ sig
}
