// bench/crypto_hotpath.nu — throughput of the AEAD record protection a
// pure-NURL TLS connection runs every byte through, measured without a
// socket in the way. Run directly:
//
//     ./nurl.sh -O2 bench/crypto_hotpath.nu bench/_build/crypto && bench/_build/crypto
//
// One "op" is one 16384-byte record — the largest TLS 1.3 allows, and so
// the size the record layer actually works in. Reported as ns/op,
// allocations/op and the MB/s those imply, because MB/s is the number a
// download is felt in.
//
// Both suites TLS 1.3 defines are here: ChaCha20-Poly1305, which is what
// NURL negotiates by default and what a host with no AES instructions
// wants, and AES-128-GCM for the servers that pick it.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bench.nu`
$ `stdlib/std/chacha20poly1305.nu`
$ `stdlib/std/aes_gcm.nu`

// A TLS record's plaintext limit (RFC 8446 §5.1).
@ record_size → i { ^ 16384 }

@ filled i n i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u & + seed * k 31 255 ) = k + k 1 }
    ^ v
}

// ns/op over a 16 KB record → MB/s to one decimal. Whole MB/s would
// print the AES suite as `0`, and the point of this table is that the
// two suites are three orders of magnitude apart. (`nurl_print_int` ends
// its own line, so the digits go through `nurl_str_int` instead.)
@ report_mbps s label i ns_per_op → v {
    : i tenths ? > ns_per_op 0 / * ( record_size ) 10000 ns_per_op 0
    ( nurl_print label )
    ( nurl_print `: ` )
    ( nurl_print ( nurl_str_int / tenths 10 ) )
    ( nurl_print `.` )
    ( nurl_print ( nurl_str_int % tenths 10 ) )
    ( nurl_print ` MB/s\n\n` )
}

@ main → i {
    : i n ( record_size )
    : ( Vec u ) key32 ( filled 32 7 )
    : ( Vec u ) key16 ( filled 16 7 )
    : ( Vec u ) nonce ( filled 12 3 )
    : ( Vec u ) aad ( filled 5 1 )
    : ( Vec u ) pt ( filled n 11 )
    : ( Vec u ) sealed_cc ( aead_encrypt key32 nonce aad pt )
    : ( Vec u ) sealed_gcm ( aes128_gcm_encrypt key16 nonce aad pt )

    ( nurl_print `AEAD record throughput, ` )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `-byte records (ns/op, allocs/op):\n\n` )

    : ( @ v ) b_cc_seal \ → v {
        : ( Vec u ) c ( aead_encrypt key32 nonce aad pt )
        ( vec_free [u] c )
    }
    : BenchResult r1 ( bench_auto `chacha20poly1305_seal` b_cc_seal )
    ( bench_report r1 )
    ( report_mbps `chacha20poly1305_seal` . r1 ns_per_op )
    ( bench_result_free r1 )

    : ( @ v ) b_cc_open \ → v {
        ?? ( aead_decrypt key32 nonce aad sealed_cc ) {
            T p → { ( vec_free [u] p ) }
            F _ → {}
        }
    }
    : BenchResult r2 ( bench_auto `chacha20poly1305_open` b_cc_open )
    ( bench_report r2 )
    ( report_mbps `chacha20poly1305_open` . r2 ns_per_op )
    ( bench_result_free r2 )

    : ( @ v ) b_gcm_seal \ → v {
        : ( Vec u ) c ( aes128_gcm_encrypt key16 nonce aad pt )
        ( vec_free [u] c )
    }
    : BenchResult r3 ( bench_auto `aes128_gcm_seal` b_gcm_seal )
    ( bench_report r3 )
    ( report_mbps `aes128_gcm_seal` . r3 ns_per_op )
    ( bench_result_free r3 )

    : ( @ v ) b_gcm_open \ → v {
        ?? ( aes128_gcm_decrypt key16 nonce aad sealed_gcm ) {
            T p → { ( vec_free [u] p ) }
            F _ → {}
        }
    }
    : BenchResult r4 ( bench_auto `aes128_gcm_open` b_gcm_open )
    ( bench_report r4 )
    ( report_mbps `aes128_gcm_open` . r4 ns_per_op )
    ( bench_result_free r4 )

    ( vec_free [u] key32 )
    ( vec_free [u] key16 )
    ( vec_free [u] nonce )
    ( vec_free [u] aad )
    ( vec_free [u] pt )
    ( vec_free [u] sealed_cc )
    ( vec_free [u] sealed_gcm )
    ^ 0
}
