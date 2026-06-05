// Regression: RFC 4648 §10 Base32 test vectors (the alphabet RFC 6238
// TOTP secrets use). Exercises the binary-safe MSB-first encoder, the
// `=` padding to an 8-char boundary, and the case-insensitive,
// whitespace-skipping, padding-optional decoder.
//
//   ""       → ""
//   "f"      → "MY======"
//   "fo"     → "MZXQ===="
//   "foo"    → "MZXW6==="
//   "foob"   → "MZXW6YQ="
//   "fooba"  → "MZXW6YTB"
//   "foobar" → "MZXW6YTBOI======"
//
// Prints PASS / FAIL lines and returns the failure count, so a broken
// codec surfaces in the suite's failures.txt with a non-zero exit.

$ `stdlib/std/encode.nu`
$ `stdlib/core/string.nu`

// Encode `in`, compare to `exp`; decode `exp`, compare to `in`.
// Returns the number of mismatches (0 = both directions correct).
@ rt s in s exp → i {
    : ~ i fails 0
    : String enc ( b32_encode in )
    : String want ( string_from exp )
    ? ! ( string_eq enc want ) {
        ( nurl_print `  enc FAIL "` )
        ( nurl_print in )
        ( nurl_print `" got "` )
        ( nurl_print ( string_data enc ) )
        ( nurl_print `" want "` )
        ( nurl_print exp )
        ( nurl_print `"\n` )
        = fails + fails 1
    } {}
    ( string_free enc )
    ( string_free want )
    : !String ParseErr dr ( b32_decode exp )
    ?? dr {
        T dec → {
            : String iin ( string_from in )
            ? ! ( string_eq dec iin ) {
                ( nurl_print `  dec FAIL "` )
                ( nurl_print exp )
                ( nurl_print `"\n` )
                = fails + fails 1
            } {}
            ( string_free dec )
            ( string_free iin )
        }
        F → {
            ( nurl_print `  dec ERR "` )
            ( nurl_print exp )
            ( nurl_print `"\n` )
            = fails + fails 1
        }
    }
    ^ fails
}

@ main → i {
    : ~ i fails 0
    = fails + fails ( rt `` `` )
    = fails + fails ( rt `f` `MY======` )
    = fails + fails ( rt `fo` `MZXQ====` )
    = fails + fails ( rt `foo` `MZXW6===` )
    = fails + fails ( rt `foob` `MZXW6YQ=` )
    = fails + fails ( rt `fooba` `MZXW6YTB` )
    = fails + fails ( rt `foobar` `MZXW6YTBOI======` )

    // TOTP-style decode: lowercase + embedded whitespace + no padding
    // must still recover the original bytes.
    : !String ParseErr lr ( b32_decode `mzxw 6ytb oi` )
    ?? lr {
        T dec → {
            : String want ( string_from `foobar` )
            ? ! ( string_eq dec want ) {
                ( nurl_print `  lax-decode FAIL\n` )
                = fails + fails 1
            } {}
            ( string_free dec )
            ( string_free want )
        }
        F → {
            ( nurl_print `  lax-decode ERR\n` )
            = fails + fails 1
        }
    }

    // Malformed input ('1' and '8' are outside the A-Z2-7 alphabet)
    // must be rejected, not silently accepted.
    : !String ParseErr br ( b32_decode `MZXW6Y18` )
    ?? br {
        T bad → {
            ( nurl_print `  reject FAIL: accepted bad alphabet\n` )
            ( string_free bad )
            = fails + fails 1
        }
        F → {}
    }

    ? == fails 0 {
        ( nurl_print `base32: all vectors PASS\n` )
    } {
        ( nurl_print `base32: ` )
        ( nurl_print ( nurl_str_int fails ) )
        ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
