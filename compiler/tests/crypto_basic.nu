// Test: stdlib/std/encode.nu + stdlib/std/hash.nu + stdlib/std/random.nu
//
// Vectors:
//   * SHA-256 — FIPS 180-4 examples (empty, "abc", 56-byte block-edge case)
//   * HMAC-SHA-256 — well-known reference outputs ("key" + the fox sentence,
//                    empty/empty)
//   * Base64 — RFC 4648 §10 vectors and round-trips
//   * Hex   — round-trip + decode-error path
// Random output is non-deterministic, so the test only checks shape:
//   - rand_hex_str(8) emits exactly 16 lowercase hex chars
//   - rand_range(10, 20) lands inside the half-open interval

$ `stdlib/std/encode.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/std/random.nu`

@ check s label String got s want → v {
    ? ( nurl_str_eq ( string_data got ) want ) {
        ( nurl_print `ok ` )
        ( nurl_print label )
        ( nurl_print `\n` )
    } {
        ( nurl_print `FAIL ` )
        ( nurl_print label )
        ( nurl_print ` got=` )
        ( nurl_print ( string_data got ) )
        ( nurl_print ` want=` )
        ( nurl_print want )
        ( nurl_print `\n` )
    }
    ( string_free got )
}

// Show decoded bytes as a hex round-trip so the test snapshot stays
// printable — raw decoded bytes may include non-ASCII (e.g. 0xfb).
@ show_dec_hex s label ! String ParseErr r → v {
    ?? r {
        T s → {
            : String h ( hex_encode ( string_data s ) )
            ( nurl_print `ok ` )
            ( nurl_print label )
            ( nurl_print ` -> ` )
            ( nurl_print ( string_data h ) )
            ( nurl_print `\n` )
            ( string_free h )
            ( string_free s )
        }
        F e → {
            ( nurl_print `err ` )
            ( nurl_print label )
            ( nurl_print ` -> ` )
            ( nurl_print ( parse_err_msg e ) )
            ( nurl_print `\n` )
        }
    }
}

@ show_dec_str s label ! String ParseErr r → v {
    ?? r {
        T s → {
            ( nurl_print `ok ` )
            ( nurl_print label )
            ( nurl_print ` -> ` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F e → {
            ( nurl_print `err ` )
            ( nurl_print label )
            ( nurl_print ` -> ` )
            ( nurl_print ( parse_err_msg e ) )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    // ── SHA-256 ──
    ( check `sha256("")`
    ( sha256_hex `` )
    `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` )
    ( check `sha256("abc")`
    ( sha256_hex `abc` )
    `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` )
    ( check `sha256(56-byte)`
    ( sha256_hex `abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq` )
    `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` )

    // ── HMAC-SHA-256 ──
    ( check `hmac("","")`
    ( hmac_sha256_hex `` `` )
    `b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad` )
    ( check `hmac(key,fox)`
    ( hmac_sha256_hex `key` `The quick brown fox jumps over the lazy dog` )
    `f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8` )

    // ── Base64 (RFC 4648 §10) ──
    ( check `b64("")` ( b64_encode `` ) `` )
    ( check `b64("f")` ( b64_encode `f` ) `Zg==` )
    ( check `b64("fo")` ( b64_encode `fo` ) `Zm8=` )
    ( check `b64("foo")` ( b64_encode `foo` ) `Zm9v` )
    ( check `b64("foob")` ( b64_encode `foob` ) `Zm9vYg==` )
    ( check `b64("fooba")` ( b64_encode `fooba` ) `Zm9vYmE=` )
    ( check `b64("foobar")` ( b64_encode `foobar` ) `Zm9vYmFy` )

    // Decode round-trip — printable ASCII payloads, so use string form.
    ( show_dec_str `b64d("Zm9vYmFy")` ( b64_decode `Zm9vYmFy` ) )
    ( show_dec_str `b64d("Zm9vYg==")` ( b64_decode `Zm9vYg==` ) )
    ( show_dec_str `b64d("Zg==")` ( b64_decode `Zg==` ) )

    // URL-safe alphabet (no padding). Plain bytes 0xfb 0xff 0xff yields
    // standard "+///" and URL-safe "-___".
    : String tri ( string_new )
    ( string_push_char tri 251 )
    ( string_push_char tri 255 )
    ( string_push_char tri 255 )
    ( check `b64_url(0xfb 0xff 0xff)` ( b64_url_encode ( string_data tri ) ) `-___` )
    ( check `b64_std(0xfb 0xff 0xff)` ( b64_encode ( string_data tri ) ) `+///` )
    ( string_free tri )
    ( show_dec_hex `b64_url("-___")` ( b64_url_decode `-___` ) )

    // Decode failure: bad char / non-padding-after-pad
    ( show_dec_str `b64d("a===")` ( b64_decode `a===` ) )
    ( show_dec_str `b64d("@@@@")` ( b64_decode `@@@@` ) )

    // ── Hex ──
    ( check `hex("hi!")` ( hex_encode `hi!` ) `686921` )
    ( show_dec_hex `hexd("DEADBEEF")` ( hex_decode `DEADBEEF` ) )
    ( show_dec_str `hexd("Z0")` ( hex_decode `Z0` ) )
    ( show_dec_str `hexd("abc")` ( hex_decode `abc` ) )
    ( show_dec_str `hexd("")` ( hex_decode `` ) )

    // ── Random sanity ──
    : String r1 ( rand_hex_str 8 )
    : String r2 ( rand_hex_str 8 )
    ? == 16 ( string_len r1 ) {
        ( nurl_print `ok rand_hex_str(8) length\n` )
    } {
        ( nurl_print `FAIL rand_hex_str(8) length=` )
        ( nurl_print ( nurl_str_int ( string_len r1 ) ) )
        ( nurl_print `\n` )
    }
    ? ! ( string_eq r1 r2 ) {
        ( nurl_print `ok rand_hex_str non-degenerate\n` )
    } {
        ( nurl_print `FAIL rand_hex_str collision\n` )
    }
    ( string_free r1 )
    ( string_free r2 )

    : ~ b range_ok T
    : ~ i k 0
    ~ < k 50 {
        : i v ( rand_range 10 20 )
        ? | < v 10 >= v 20 { = range_ok F } {}
        = k + k 1
    }
    ? range_ok { ( nurl_print `ok rand_range bounds\n` ) }
    { ( nurl_print `FAIL rand_range bounds\n` ) }

    ( nurl_print `done\n` )
    ^ 0
}
