// pqc — post-quantum key encapsulation on the command line, and a
// probe for whether the servers you talk to are ready for it.
//
//   pqc keygen [-l 768] -o NAME    write NAME.ek and NAME.dk
//   pqc encaps NAME.ek             → NAME.ct and the shared secret
//   pqc decaps NAME.dk NAME.ct     → the same shared secret
//   pqc sign-keygen [-l 65] -o N   write N.pub and N.key   (ML-DSA)
//   pqc sign N.key FILE            → FILE.sig
//   pqc verify N.pub FILE FILE.sig → valid / INVALID
//   pqc probe HOST[:PORT]…         does this server do post-quantum TLS?
//   pqc bench [-l 768] [-n N]      operations per second, here
//   pqc kat                        self-test against NIST's vectors
//
// Two schemes, one tool: ML-KEM (FIPS 203) replaces the key exchange
// and ML-DSA (FIPS 204) replaces the signature. The KEM levels are 512,
// 768 and 1024; the signature levels are 44, 65 and 87, and `-l` picks
// whichever family the subcommand belongs to.
//
// ML-KEM (FIPS 203) is the KEM NIST standardised in 2024, and the
// `probe` subcommand is the part worth having on a laptop: it completes
// a real TLS 1.3 handshake and reports which key-exchange group the
// server actually chose. Offering the hybrid group is not the same as
// getting it — a server that has not deployed ML-KEM falls back to
// X25519 silently, and from every other angle the handshake looks the
// same. This tells you which one happened.
//
// Everything here is pure NURL over stdlib/std/mlkem.nu and
// stdlib/std/tls.nu: no libcrypto, no liboqs.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/mlkem.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/ext/env.nu`

@ __die s msg → v {
    ( nurl_eprint `pqc: ` ) ( nurl_eprint msg ) ( nurl_eprint `\n` )
}

@ __free_strvec ( Vec String ) v → v {
    ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
}

@ __pos ( Vec String ) ps i k → s {
    ^ ?? ( vec_get [String] ps k ) { T s → ( string_data s ) F _ → `` }
}

@ __opt_int ArgParser p s name i dflt → i {
    ?? ( args_value p name ) {
        T v → { : i n ( nurl_str_to_int ( string_data v ) ) ( string_free v ) ^ n }
        F _ → { ^ dflt }
    }
}

@ __opt_str ArgParser p s name s dflt → String {
    ^ ( args_value_or p name dflt )
}

// A level the standard actually defines. Anything else is a typo, and
// silently rounding it to 768 would hand back keys of a size the caller
// did not ask for.
@ __check_level i level → b {
    ^ | | == level 512 == level 768 == level 1024
}

@ __read_bytes s path → !( Vec u ) IoErr {
    ^ ( read_file_bytes path )
}

@ __write_bytes s path ( Vec u ) v s what → b {
    : !v IoErr r ( write_file_bytes path v )
    ?? r {
        T _ → {
            : String ln ( __line_new what )
            ( string_push_str ln ` ` )
            ( string_push_str ln path )
            ( string_push_str ln ` (` )
            ( __line_int ln ( vec_len [u] v ) )
            ( string_push_str ln ` bytes)` )
            ( __line_end ln )
            ^ T
        }
        F _e → { ( __die `cannot write output file` ) ^ F }
    }
}

// `nurl_println_int` ends its own line, which is right for a bare number
// and wrong for a number inside a sentence. Lines with a number in the
// middle are assembled as a String and printed once.
@ __line_new s head → String {
    : String s ( string_new )
    ( string_push_str s head )
    ^ s
}

@ __line_int String s i n → v {
    ( string_push_int s n )
}

@ __line_end String s → v {
    ( string_push_str s `\n` )
    ( nurl_print ( string_data s ) )
    ( string_free s )
}

@ __print_hex s label ( Vec u ) v → v {
    : String h ( bytes_to_hex v )
    ( nurl_print label ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
    ( string_free h )
}

// ── keygen ─────────────────────────────────────────────────────────

@ __cmd_keygen i level s name → i {
    : *MlkemKeys ks ( mlkem_keygen level )
    : String ekp ( string_from name ) ( string_push_str ekp `.ek` )
    : String dkp ( string_from name ) ( string_push_str dkp `.dk` )
    : b a ( __write_bytes ( string_data ekp ) ( mlkem_ek ks ) `encapsulation key ->` )
    : b b2 ( __write_bytes ( string_data dkp ) ( mlkem_dk ks ) `decapsulation key ->` )
    ( string_free dkp ) ( string_free ekp )
    ( mlkem_keys_free ks )
    ^ ? & a b2 0 1
}

// ── encaps ─────────────────────────────────────────────────────────
//
// The level is inferred from the encapsulation key's length rather than
// asked for: the three sizes are distinct, and a caller who has the key
// should not have to remember which parameter set produced it.

@ __level_from_ek i n → i {
    ? == n 800 { ^ 512 } {}
    ? == n 1184 { ^ 768 } {}
    ? == n 1568 { ^ 1024 } {}
    ^ 0
}

@ __level_from_dk i n → i {
    ? == n 1632 { ^ 512 } {}
    ? == n 2400 { ^ 768 } {}
    ? == n 3168 { ^ 1024 } {}
    ^ 0
}

@ __cmd_encaps s ekpath s outpath → i {
    : !( Vec u ) IoErr r ( __read_bytes ekpath )
    ?? r {
        T ek → {
            : i level ( __level_from_ek ( vec_len [u] ek ) )
            ? == level 0 {
                ( __die `not an ML-KEM encapsulation key (expected 800, 1184 or 1568 bytes)` )
                ( vec_free [u] ek )
                ^ 1
            } {}
            : *MlkemEncap en ( mlkem_encaps level ek )
            : String hd ( __line_new `ML-KEM-` )
            ( __line_int hd level ) ( __line_end hd )
            : b ok ( __write_bytes outpath ( mlkem_ct en ) `ciphertext ->` )
            ( __print_hex `shared secret ` ( mlkem_ss en ) )
            ( mlkem_encap_free en )
            ( vec_free [u] ek )
            ^ ? ok 0 1
        }
        F _e → { ( __die `cannot read encapsulation key` ) ^ 1 }
    }
}

@ __cmd_decaps s dkpath s ctpath → i {
    : !( Vec u ) IoErr rd ( __read_bytes dkpath )
    ?? rd {
        T dk → {
            : i level ( __level_from_dk ( vec_len [u] dk ) )
            ? == level 0 {
                ( __die `not an ML-KEM decapsulation key (expected 1632, 2400 or 3168 bytes)` )
                ( vec_free [u] dk )
                ^ 1
            } {}
            : !( Vec u ) IoErr rc ( __read_bytes ctpath )
            ?? rc {
                T ct → {
                    ? != ( vec_len [u] ct ) ( mlkem_ct_len level ) {
                        // Decapsulation of a wrong-length ciphertext is not
                        // defined; it is the one input error ML-KEM cannot
                        // absorb into implicit rejection.
                        ( __die `ciphertext length does not match this key's parameter set` )
                        ( vec_free [u] ct ) ( vec_free [u] dk )
                        ^ 1
                    } {}
                    : ( Vec u ) ss ( mlkem_decaps level dk ct )
                    : String hd ( __line_new `ML-KEM-` )
                    ( __line_int hd level ) ( __line_end hd )
                    ( __print_hex `shared secret ` ss )
                    ( vec_free [u] ss ) ( vec_free [u] ct ) ( vec_free [u] dk )
                    ^ 0
                }
                F _e → { ( __die `cannot read ciphertext` ) ( vec_free [u] dk ) ^ 1 }
            }
        }
        F _e → { ( __die `cannot read decapsulation key` ) ^ 1 }
    }
}

// ── ML-DSA signing ─────────────────────────────────────────────────

@ __check_sign_level i level → b {
    ^ | | == level 44 == level 65 == level 87
}

@ __level_from_pub i n → i {
    ? == n 1312 { ^ 44 } {}
    ? == n 1952 { ^ 65 } {}
    ? == n 2592 { ^ 87 } {}
    ^ 0
}

@ __level_from_key i n → i {
    ? == n 2560 { ^ 44 } {}
    ? == n 4032 { ^ 65 } {}
    ? == n 4896 { ^ 87 } {}
    ^ 0
}

@ __cmd_sign_keygen i level s name → i {
    : *MldsaKeys ks ( mldsa_keygen level )
    : String pp ( string_from name ) ( string_push_str pp `.pub` )
    : String kp2 ( string_from name ) ( string_push_str kp2 `.key` )
    : b a ( __write_bytes ( string_data pp ) ( mldsa_pk ks ) `verification key ->` )
    : b b2 ( __write_bytes ( string_data kp2 ) ( mldsa_sk ks ) `signing key ->` )
    ( string_free kp2 ) ( string_free pp )
    ( mldsa_keys_free ks )
    ^ ? & a b2 0 1
}

// The context string binds a signature to this tool, so a signature
// made by `pqc sign` cannot be replayed as one made for some other
// application that happens to use the same key.
@ __pqc_ctx → ( Vec u ) {
    : ( Vec u ) c ( vec_new [u] )
    ( bytes_extend_str c `pqc` )
    ^ c
}

@ __cmd_sign s keypath s msgpath s outpath → i {
    : !( Vec u ) IoErr rk ( __read_bytes keypath )
    ?? rk {
        T sk → {
            : i level ( __level_from_key ( vec_len [u] sk ) )
            ? == level 0 {
                ( __die `not an ML-DSA signing key (expected 2560, 4032 or 4896 bytes)` )
                ( vec_free [u] sk )
                ^ 1
            } {}
            : !( Vec u ) IoErr rm ( __read_bytes msgpath )
            ?? rm {
                T msg → {
                    : ( Vec u ) ctx ( __pqc_ctx )
                    : ( Vec u ) sig ( mldsa_sign level sk msg ctx )
                    : String hd ( __line_new `ML-DSA-` )
                    ( __line_int hd level ) ( __line_end hd )
                    : b ok ( __write_bytes outpath sig `signature ->` )
                    ( vec_free [u] sig ) ( vec_free [u] ctx )
                    ( vec_free [u] msg ) ( vec_free [u] sk )
                    ^ ? ok 0 1
                }
                F _e → { ( __die `cannot read the file to sign` ) ( vec_free [u] sk ) ^ 1 }
            }
        }
        F _e → { ( __die `cannot read signing key` ) ^ 1 }
    }
}

@ __cmd_verify s pubpath s msgpath s sigpath → i {
    : !( Vec u ) IoErr rp ( __read_bytes pubpath )
    ?? rp {
        T pk → {
            : i level ( __level_from_pub ( vec_len [u] pk ) )
            ? == level 0 {
                ( __die `not an ML-DSA verification key (expected 1312, 1952 or 2592 bytes)` )
                ( vec_free [u] pk )
                ^ 1
            } {}
            : !( Vec u ) IoErr rm ( __read_bytes msgpath )
            ?? rm {
                T msg → {
                    : !( Vec u ) IoErr rs ( __read_bytes sigpath )
                    ?? rs {
                        T sig → {
                            : ( Vec u ) ctx ( __pqc_ctx )
                            : b ok ( mldsa_verify level pk msg ctx sig )
                            : String ln ( __line_new `ML-DSA-` )
                            ( __line_int ln level )
                            ( string_push_str ln ? ok ` valid` ` INVALID` )
                            ( __line_end ln )
                            ( vec_free [u] ctx ) ( vec_free [u] sig )
                            ( vec_free [u] msg ) ( vec_free [u] pk )
                            ^ ? ok 0 1
                        }
                        F _e → { ( __die `cannot read signature` ) ( vec_free [u] msg ) ( vec_free [u] pk ) ^ 1 }
                    }
                }
                F _e → { ( __die `cannot read the signed file` ) ( vec_free [u] pk ) ^ 1 }
            }
        }
        F _e → { ( __die `cannot read verification key` ) ^ 1 }
    }
}

// ── probe ──────────────────────────────────────────────────────────

@ __group_name i g → s {
    ? == g 4588 { ^ `X25519MLKEM768` } {}
    ? == g 29 { ^ `x25519` } {}
    ? == g 23 { ^ `secp256r1` } {}
    ^ `(none)`
}

@ __pad s host → v {
    ( nurl_print host )
    : i n ( nurl_str_len host )
    : ~ i k n
    ~ < k 34 { ( nurl_print ` ` ) = k + k 1 }
}

// The probe's question is "does this server negotiate a post-quantum
// group", and the handshake answers it whether or not the certificate
// chains to a root this machine trusts. So probe first with
// verification, and on TlsBadCert retry insecurely: the group is real
// either way, and the output says the trust half separately. The old
// spelling used only the verifying connect, so a self-signed lab server
// that negotiated X25519MLKEM768 perfectly was reported "handshake
// failed" — conflating "not post-quantum" with "not trusted", which are
// exactly the two things a probe exists to keep apart.
@ __cmd_probe s host i port → i {
    ( __pad host )
    : ~ b trusted T
    : ~ * TlsConn conn # *TlsConn 0
    ?? ( tls_connect host port host ) {
        T c → { = conn c }
        F e → {
            ?? e {
                TlsBadCert → {
                    = trusted F
                    ?? ( tls_connect_insecure host port host ) {
                        T c2 → { = conn c2 }
                        F _e2 → {}
                    }
                }
                _ → {}
            }
        }
    }
    ? == # i conn 0 {
        ( nurl_print `--   handshake failed\n` )
        ^ 2
    } {}
    : i g ( tls_group conn )
    : b pq ( tls_is_post_quantum conn )
    ( nurl_print ? pq `PQ   ` `no   ` )
    ( nurl_print ( __group_name g ) )
    ? ! trusted { ( nurl_print `   (certificate UNTRUSTED here)` ) } {}
    ( nurl_print `\n` )
    ( tls_close conn )
    ^ ? pq 0 1
}

// ── bench ──────────────────────────────────────────────────────────

// Operations per second from an elapsed nanosecond count. Integer
// throughout: n·10^9 stays far below i64 range for any plausible reps,
// and a float round-trip would only add noise to a printed rate.
@ __rate String ln i ns i n → v {
    ? > ns 0 {
        ( __line_int ln / * n 1000000000 ns )
        ( string_push_str ln ` op/s` )
    } { ( string_push_str ln `too fast to time` ) }
}

@ __cmd_bench i level i reps → i {
    : String hd ( __line_new `ML-KEM-` )
    ( __line_int hd level )
    ( string_push_str hd `  ` )
    ( __line_int hd reps )
    ( string_push_str hd ` iterations` )
    ( __line_end hd )

    : i t0 ( monotonic_ns )
    : ~ i i 0
    : ~ i sink 0
    ~ < i reps {
        : *MlkemKeys ks ( mlkem_keygen level )
        = sink + sink ( vec_len [u] ( mlkem_ek ks ) )
        ( mlkem_keys_free ks )
        = i + i 1
    }
    : i t1 ( monotonic_ns )
    : String l_keygen ( __line_new `  keygen  ` )
    ( __rate l_keygen - t1 t0 reps )
    ( __line_end l_keygen )

    : *MlkemKeys ks ( mlkem_keygen level )
    : i t2 ( monotonic_ns )
    = i 0
    ~ < i reps {
        : *MlkemEncap en ( mlkem_encaps level ( mlkem_ek ks ) )
        = sink + sink ( vec_len [u] ( mlkem_ct en ) )
        ( mlkem_encap_free en )
        = i + i 1
    }
    : i t3 ( monotonic_ns )
    : String l_encaps ( __line_new `  encaps  ` )
    ( __rate l_encaps - t3 t2 reps )
    ( __line_end l_encaps )

    : *MlkemEncap en ( mlkem_encaps level ( mlkem_ek ks ) )
    : i t4 ( monotonic_ns )
    = i 0
    ~ < i reps {
        : ( Vec u ) ss ( mlkem_decaps level ( mlkem_dk ks ) ( mlkem_ct en ) )
        = sink + sink ( vec_len [u] ss )
        ( vec_free [u] ss )
        = i + i 1
    }
    : i t5 ( monotonic_ns )
    : String l_decaps ( __line_new `  decaps  ` )
    ( __rate l_decaps - t5 t4 reps )
    ( __line_end l_decaps )
    ( mlkem_encap_free en )
    ( mlkem_keys_free ks )
    ^ ? > sink 0 0 1
}

// ── kat ────────────────────────────────────────────────────────────
//
// One NIST ACVP key-generation vector per parameter set, pinned by the
// SHA3-256 of the expected ek and dk, plus a round trip and the
// implicit-rejection path. The compiler repo's
// compiler/tests/mlkem_vectors.nu carries the wider set and
// tools/mlkem_acvp_gate.sh runs all 180 published cases.

@ __hexv s h → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex h )
    ?? r { T v → { ^ v } F _e → { ^ ( vec_new [u] ) } }
}

@ __digest_is ( Vec u ) v s want → b {
    : ( Vec u ) d ( sha3_256_pure v )
    : String h ( bytes_to_hex d )
    : b ok != 0 ( nurl_str_eq ( string_data h ) want )
    ( string_free h ) ( vec_free [u] d )
    ^ ok
}

@ __kat_one s label i level s d s z s ekd s dkd → b {
    : ( Vec u ) dv ( __hexv d )
    : ( Vec u ) zv ( __hexv z )
    : *MlkemKeys ks ( mlkem_keygen_derand level dv zv )
    : b ok & ( __digest_is ( mlkem_ek ks ) ekd ) ( __digest_is ( mlkem_dk ks ) dkd )

    // Round trip, then the rejection path on a corrupted ciphertext.
    : ( Vec u ) m ( __hexv `4e77596168711e913965d8175ac3bd76aab08b7f9385a02ae883cf6c6e17dd81` )
    : *MlkemEncap en ( mlkem_encaps_derand level ( mlkem_ek ks ) m )
    : ( Vec u ) ss ( mlkem_decaps level ( mlkem_dk ks ) ( mlkem_ct en ) )
    : b okrt ( bytes_eq ss ( mlkem_ss en ) )
    : ( Vec u ) bad ( bytes_slice ( mlkem_ct en ) 0 ( vec_len [u] ( mlkem_ct en ) ) )
    : *u bp ( vec_data [u] bad )
    = . bp 0 # u ^^ # i . bp 0 1
    : ( Vec u ) rej ( mlkem_decaps level ( mlkem_dk ks ) bad )
    : b okrej & ! ( bytes_eq rej ss ) == ( vec_len [u] rej ) 32

    ( nurl_print label )
    ( nurl_print ? & & ok okrt okrej ` ok\n` ` FAIL\n` )
    ( vec_free [u] rej ) ( vec_free [u] bad ) ( vec_free [u] ss )
    ( mlkem_encap_free en ) ( vec_free [u] m )
    ( mlkem_keys_free ks ) ( vec_free [u] zv ) ( vec_free [u] dv )
    ^ & & ok okrt okrej
}

@ __cmd_kat → i {
    : ~ b all T
    = all & all ( __kat_one `ML-KEM-512 ` 512
    `47b893474672ba92e4b12ee44fb32953af8e8503b5fb471d1614fb8a021a660a`
    `1f8cb39e9e30bc458a0dc5408884b1187fb217018df760fa57317703b844a0a9`
    `3a389831056ed8fd81476869245782689c84b3ce90fe6a9e78d0a380fd6a1573`
    `c26aff5b9f97b5b9ca824755d053a1b1aece2b965af6bfbd527b77ea22538468` )
    = all & all ( __kat_one `ML-KEM-768 ` 768
    `e582b7d75e6c80b05ae392a1fc9f7153b12390fd99930368cc67a768baebc8a0`
    `1cdacb8740c0b87c4a379575f187b367cbfa3b300bf591b109f79816e9cbe8f0`
    `81e66ef5a7a221619f6a64039cc369843e10df5c859f6959cc3fd8e5272330fd`
    `be81068c104cd6cf8efd800b294f4a15bb8a8050993fd54a2cc428841ef6ca44` )
    = all & all ( __kat_one `ML-KEM-1024` 1024
    `f3a706faf090c03db506863ab0b20bd8a1627956318e88c67eb875e8e7266009`
    `35d2bc43dd1cc879f765bf2a0c5e297889dde910e57e2bb0eae417b90ab7a275`
    `9370fe5b05ddc92c939f62cbde4c0fea36f45cd20c5748cf3ac891a4c2604496`
    `b8c683c71564ff8e2391c57b68c3a1ff186734b13e31d2a075b65307c8b80888` )
    ^ ? all 0 1
}

// ── driver ─────────────────────────────────────────────────────────

@ __usage ArgParser p → v {
    : String u ( args_usage p )
    ( nurl_print ( string_data u ) )
    ( string_free u )
    ( nurl_print `\ncommands:\n` )
    ( nurl_print `  keygen NAME          write NAME.ek and NAME.dk\n` )
    ( nurl_print `  encaps NAME.ek       encapsulate to a fresh shared secret\n` )
    ( nurl_print `  decaps NAME.dk CT    recover the shared secret\n` )
    ( nurl_print `  sign-keygen NAME     write NAME.pub and NAME.key (ML-DSA)\n` )
    ( nurl_print `  sign KEY FILE        sign FILE, writing FILE.sig\n` )
    ( nurl_print `  verify PUB FILE SIG  check a signature\n` )
    ( nurl_print `  probe HOST...        report each server's TLS key-exchange group\n` )
    ( nurl_print `  bench                operations per second on this machine\n` )
    ( nurl_print `  kat                  self-test against NIST ACVP vectors\n` )
    ( nurl_print `\nlevels: ML-KEM 512, 768 (default), 1024\n` )
    ( nurl_print `        ML-DSA 44, 65 (default), 87\n` )
}

// One subcommand per clause, each returning directly.
//
// Written flat rather than as a nested if/else ladder: with nine
// subcommands the ladder's tail becomes a run of closing braces whose
// count is the only thing keeping it correct, and miscounting compiles
// into a different program rather than an error.
@ __dispatch ArgParser p ( Vec String ) ps s cmd i level → i {
    : i n ( vec_len [String] ps )

    ? != 0 ( nurl_str_eq cmd `keygen` ) {
        ? ( __check_level level ) {} { ( __die `ML-KEM level must be 512, 768 or 1024` ) ^ 2 }
        : String nm ( __opt_str p `out` ? > n 1 ( __pos ps 1 ) `mlkem` )
        : i rc ( __cmd_keygen level ( string_data nm ) )
        ( string_free nm )
        ^ rc
    } {}

    ? != 0 ( nurl_str_eq cmd `encaps` ) {
        ? < n 2 { ( __die `encaps needs an encapsulation key file` ) ^ 2 } {}
        : String o ( __opt_str p `out` `mlkem.ct` )
        : i rc ( __cmd_encaps ( __pos ps 1 ) ( string_data o ) )
        ( string_free o )
        ^ rc
    } {}

    ? != 0 ( nurl_str_eq cmd `decaps` ) {
        ? < n 3 { ( __die `decaps needs a decapsulation key and a ciphertext` ) ^ 2 } {}
        ^ ( __cmd_decaps ( __pos ps 1 ) ( __pos ps 2 ) )
    } {}

    ? != 0 ( nurl_str_eq cmd `sign-keygen` ) {
        : i sl ( __opt_int p `level` 65 )
        ? ( __check_sign_level sl ) {} { ( __die `ML-DSA level must be 44, 65 or 87` ) ^ 2 }
        : String nm ( __opt_str p `out` ? > n 1 ( __pos ps 1 ) `mldsa` )
        : i rc ( __cmd_sign_keygen sl ( string_data nm ) )
        ( string_free nm )
        ^ rc
    } {}

    ? != 0 ( nurl_str_eq cmd `sign` ) {
        ? < n 3 { ( __die `sign needs a signing key and a file` ) ^ 2 } {}
        // Default output is the input name with .sig appended.
        : String derived ( string_from ( __pos ps 2 ) )
        ( string_push_str derived `.sig` )
        : String o ( __opt_str p `out` ( string_data derived ) )
        : i rc ( __cmd_sign ( __pos ps 1 ) ( __pos ps 2 ) ( string_data o ) )
        ( string_free o )
        ( string_free derived )
        ^ rc
    } {}

    ? != 0 ( nurl_str_eq cmd `verify` ) {
        ? < n 4 { ( __die `verify needs a key, a file and a signature` ) ^ 2 } {}
        ^ ( __cmd_verify ( __pos ps 1 ) ( __pos ps 2 ) ( __pos ps 3 ) )
    } {}

    ? != 0 ( nurl_str_eq cmd `probe` ) {
        ? < n 2 { ( __die `probe needs at least one host` ) ^ 2 } {}
        : i dport ( __opt_int p `port` 443 )
        ( nurl_print `host                              PQ?  group\n` )
        : ~ i k 1
        : ~ i worst 0
        ~ < k n {
            // The usage header has always said HOST[:PORT]; honour it.
            // A trailing `:<digits>` overrides --port for that one
            // host. The split is from the RIGHT and only when the
            // suffix is all digits, so a bare IPv6 literal (which has
            // no port syntax without brackets) still passes through
            // whole rather than losing its last group.
            : s hp ( __pos ps k )
            : i hl ( nurl_str_len hp )
            : ~ i port dport
            : ~ s host hp
            // Rightmost ':' by hand (there is no rfind in the string
            // set), and the suffix after it must be all digits.
            : ~ i ci 0
            : ~ i sc 0
            : ~ i q 0
            ~ < q hl {
                ? == ( nurl_str_get hp q ) 58 { = ci q = sc + sc 1 } {}
                = q + q 1
            }
            ? & & == sc 1 >= ci 0 > - hl + ci 1 0 {
                : ~ b digits T
                : ~ i j + ci 1
                ~ & digits < j hl {
                    : i ch ( nurl_str_get hp j )
                    ? | < ch 48 > ch 57 { = digits F } {}
                    = j + j 1
                }
                ? digits {
                    = port ( nurl_str_to_int ( nurl_str_slice hp + ci 1 - hl + ci 1 ) )
                    = host ( nurl_str_slice hp 0 ci )
                } {}
            } {}
            : i r ( __cmd_probe host port )
            ? > r worst { = worst r } {}
            = k + k 1
        }
        ^ worst
    } {}

    ? != 0 ( nurl_str_eq cmd `bench` ) {
        ? ( __check_level level ) {} { ( __die `ML-KEM level must be 512, 768 or 1024` ) ^ 2 }
        ^ ( __cmd_bench level ( __opt_int p `reps` 200 ) )
    } {}

    ? != 0 ( nurl_str_eq cmd `kat` ) { ^ ( __cmd_kat ) } {}

    ( __die `unknown command (try --help)` )
    ^ 2
}

@ main → i {
    : ArgParser p ( args_new `pqc` `ML-KEM (FIPS 203) and post-quantum TLS, in pure NURL` )
    ( args_flag p `help` 104 `show this help` )
    ( args_opt p `level` 108 `N` `ML-KEM parameter set: 512, 768 or 1024 (default 768)` )
    ( args_opt p `out` 111 `FILE` `output file / name prefix` )
    ( args_opt p `port` 112 `N` `probe: TCP port (default 443)` )
    ( args_opt p `reps` 110 `N` `bench: iterations per operation (default 200)` )

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac { ( vec_push [String] argv ( env_arg ai ) ) = ai + ai 1 }
    ? ( args_parse p argv ) {} {
        ( __die ( args_error p ) )
        ( args_free p ) ( __free_strvec argv )
        ^ 2
    }
    ? | ( args_present p `help` ) == 0 ( args_positional_count p ) {
        ( __usage p )
        ( args_free p ) ( __free_strvec argv )
        ^ 0
    } {}

    : ( Vec String ) ps ( args_positionals p )
    : s cmd ( __pos ps 0 )
    : i level ( __opt_int p `level` 768 )
    : ~ i rc 0

    = rc ( __dispatch p ps cmd level )

    // `ps` is a borrow of the parser's own vector — args_free releases it.
    ( args_free p )
    ( __free_strvec argv )
    ^ rc
}
