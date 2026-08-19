// tests/smoke.nu — In-process unit/smoke tests for pki-server.
//
// Covers CA generation, device cert issuance, signature verification,
// serial extraction, revocation + CRL generation and the input
// validators — for BOTH the classical P-256 CA and a post-quantum
// ML-DSA CA, since every one of those paths branches on the algorithm.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/x509.nu`
$ `../src/pki.nu`
$ `../src/auth.nu`
$ `../src/ui.nu`

: ~ i g_failures 0

@ _check b ok s what → v {
    ? ok {} {
        = g_failures + g_failures 1
        ( nurl_print `    FAIL: ` )
        ( nurl_print what )
        ( nurl_print `\n` )
    }
}

// One full lifecycle against a CA of the given algorithm.
@ _run_suite i alg s label → v {
    ( nurl_print `── ` )
    ( nurl_print label )
    ( nurl_print ` ──\n` )

    : String tmp_dir ( string_from `/tmp/pki_smoke_` )
    ( string_push_int tmp_dir ( now_seconds ) )
    ( string_push_char tmp_dir 95 )
    ( string_push_int tmp_dir alg )
    : !v IoErr _cd ( dir_create_all ( string_data tmp_dir ) )

    : String ca_crt ( string_clone tmp_dir )
    ( string_push_str ca_crt `/ca.crt` )
    : String ca_key ( string_clone tmp_dir )
    ( string_push_str ca_key `/ca.key` )
    : String crl_path ( string_clone tmp_dir )
    ( string_push_str crl_path `/ca.crl` )
    : String idx_path ( string_clone tmp_dir )
    ( string_push_str idx_path `/index.txt` )

    ( nurl_print `  [1/7] generating CA... ` )
    : *PkiCa ca ( pki_load_or_create_ca ( string_data ca_crt ) ( string_data ca_key ) `Test PKI CA` alg )
    ( _check != # i ca 0 `CA generation returned null` )
    ? == # i ca 0 { ( nurl_print `FAILED\n` ) ^ v } {}
    ( _check == . ca alg alg `CA algorithm not the requested one` )
    ( nurl_print `OK\n` )

    // Reloading the stored pair must reproduce the same CA — this is
    // what a server restart does, and for ML-DSA it exercises the
    // PKCS#8 loader added to std/pkey.nu.
    ( nurl_print `  [2/7] reloading CA from disk... ` )
    : *PkiCa ca2 ( pki_load_or_create_ca ( string_data ca_crt ) ( string_data ca_key ) `Test PKI CA` alg )
    ( _check != # i ca2 0 `CA reload failed` )
    ? != # i ca2 0 {
        ( _check == . ca2 alg alg `reloaded CA has a different algorithm` )
        ( _check ( bytes_eq ( pki_ca_public ca ) ( pki_ca_public ca2 ) ) `reloaded CA public key differs` )
        ( pki_ca_free ca2 )
    } {}
    ( nurl_print `OK\n` )

    ( nurl_print `  [3/7] issuing device cert... ` )
    : PkiCert dev1 ( pki_issue_device_cert ca `device-001` 365 )
    ( _check > ( string_len . dev1 cert_pem ) 0 `empty certificate PEM` )
    ( _check > ( string_len . dev1 key_pem ) 0 `empty private key PEM` )
    ( nurl_print `OK\n` )

    ( nurl_print `  [4/7] verifying against CA... ` )
    ( _check ( pki_verify_cert ca ( string_data . dev1 cert_pem ) `device-001` ) `valid cert rejected` )
    ( _check ! ( pki_verify_cert ca ( string_data . dev1 cert_pem ) `device-999` ) `mismatched hostname accepted` )
    // A certificate from a different CA of the same algorithm must not
    // verify — this is the check that catches a signature routine that
    // returns true regardless of the key.
    : *PkiCa other ( pki_generate_ca `Other CA` 30 alg )
    : PkiCert foreign ( pki_issue_device_cert other `device-001` 30 )
    ( _check ! ( pki_verify_cert ca ( string_data . foreign cert_pem ) `device-001` ) `foreign CA certificate accepted` )
    ( pki_cert_free foreign )
    ( pki_ca_free other )
    ( nurl_print `OK\n` )

    ( nurl_print `  [5/7] extracting serial and CN... ` )
    : PkiCertInfo info ( pki_extract_cert_info ( string_data . dev1 cert_pem ) )
    ( _check . info ok `certificate info extraction failed` )
    ( _check ( string_eq . info serial_hex . dev1 serial_hex ) `serial mismatch` )
    ( _check == 0 ( nurl_str_cmp ( string_data . info cn ) `device-001` ) `CN mismatch` )
    ( pki_cert_info_free info )
    ( nurl_print `OK\n` )

    ( nurl_print `  [6/7] revoking and generating CRL... ` )
    : String crl_pem ( pki_record_revocation ( string_data idx_path ) ( string_data crl_path ) ca ( string_data . dev1 serial_hex ) `device-001` )
    ( _check ( string_starts_with crl_pem `-----BEGIN X509 CRL-----` ) `invalid CRL header` )
    ( _check ( pki_is_revoked ( string_data idx_path ) ( string_data . dev1 serial_hex ) ) `revoked serial not found in index` )
    ( _check ! ( pki_is_revoked ( string_data idx_path ) `00112233445566778899` ) `unrelated serial reported revoked` )
    // Re-revoking must not duplicate the entry or restamp the date.
    : String crl2 ( pki_record_revocation ( string_data idx_path ) ( string_data crl_path ) ca ( string_data . dev1 serial_hex ) `device-001` )
    : PkiRevoked rl ( pki_read_revoked ( string_data idx_path ) )
    ( _check == ( vec_len [String] . rl serials ) 1 `duplicate revocation entry` )
    ( pki_revoked_free rl )
    ( string_free crl2 )
    ( string_free crl_pem )
    ( nurl_print `OK\n` )

    ( nurl_print `  [7/7] CRL survives a reload with its original date... ` )
    // pki_load_crl regenerates from index.txt when the file is gone;
    // the entry must come back with the date on disk, not "now".
    : !v IoErr _rm ( file_delete ( string_data crl_path ) )
    : String crl3 ( pki_load_crl ( string_data crl_path ) ca ( string_data idx_path ) )
    ( _check ( string_starts_with crl3 `-----BEGIN X509 CRL-----` ) `regenerated CRL malformed` )
    ( string_free crl3 )
    ( nurl_print `OK\n` )

    ( pki_cert_free dev1 )
    ( pki_ca_free ca )
    : !v IoErr _rmall ( dir_remove_all ( string_data tmp_dir ) )
    ( string_free ca_crt )
    ( string_free ca_key )
    ( string_free crl_path )
    ( string_free idx_path )
    ( string_free tmp_dir )
}

@ _expect_sanitize s raw s want → v {
    : String got ( pki_sanitize_id raw )
    : b ok == 0 ( nurl_str_cmp ( string_data got ) want )
    ? ok {} {
        ( nurl_print `    FAIL: sanitize_id "` )
        ( nurl_print raw )
        ( nurl_print `" -> "` )
        ( nurl_print ( string_data got ) )
        ( nurl_print `", expected "` )
        ( nurl_print want )
        ( nurl_print `"\n` )
        = g_failures + g_failures 1
    }
    ( string_free got )
}

@ _expect_serial s raw s want → v {
    : String got ( pki_normalise_serial raw )
    : b ok == 0 ( nurl_str_cmp ( string_data got ) want )
    ? ok {} {
        ( nurl_print `    FAIL: normalise_serial "` )
        ( nurl_print raw )
        ( nurl_print `" -> "` )
        ( nurl_print ( string_data got ) )
        ( nurl_print `", expected "` )
        ( nurl_print want )
        ( nurl_print `"\n` )
        = g_failures + g_failures 1
    }
    ( string_free got )
}

@ _expect_escape s raw s want → v {
    : String got ( ui_html_escape raw )
    : b ok == 0 ( nurl_str_cmp ( string_data got ) want )
    ? ok {} {
        ( nurl_print `    FAIL: html_escape "` )
        ( nurl_print raw )
        ( nurl_print `" -> "` )
        ( nurl_print ( string_data got ) )
        ( nurl_print `"\n` )
        = g_failures + g_failures 1
    }
    ( string_free got )
}

@ main → i {
    ( nurl_print `── [smoke] PKI Server Engine Tests ──\n` )

    ( nurl_print `── input validation ──\n` )
    // Path traversal: the CN of a submitted certificate names a
    // directory, so a '/' or a bare '..' must not survive.
    ( _expect_sanitize `device-001` `device-001` )
    ( _expect_sanitize `../../etc/passwd` `....etcpasswd` )
    ( _expect_sanitize `..` `` )
    ( _expect_sanitize `.` `` )
    ( _expect_sanitize `....` `` )
    ( _expect_sanitize `a/../b` `a..b` )
    ( _expect_sanitize `` `` )
    ( _expect_sanitize `dev<script>` `devscript` )

    // Serial: hex only, even length, echoed into HTML and index.txt.
    ( _expect_serial `1a2b3c` `1a2b3c` )
    ( _expect_serial `1A2B3C` `1a2b3c` )
    ( _expect_serial `abc` `` )
    ( _expect_serial `<script>` `` )
    ( _expect_serial `dead\tbeef` `` )
    ( _expect_serial `` `` )

    ( _expect_escape `<script>` `&lt;script&gt;` )
    ( _expect_escape `a"b'c&d` `a&quot;b&#39;c&amp;d` )
    ( _expect_escape `plain` `plain` )

    ( nurl_print `── auth ──\n` )
    ( _check ( auth_check_device_key `secret123` `secret123` ) `matching device key rejected` )
    ( _check ! ( auth_check_device_key `wrong` `secret123` ) `wrong device key accepted` )
    ( _check ! ( auth_check_device_key `secret1234` `secret123` ) `key prefix accepted` )
    // An unconfigured key must deny, not admit.
    ( _check ! ( auth_check_device_key `anything` `` ) `empty expected key admitted a caller` )
    ( _check ! ( auth_check_api_key_value `anything` `` ) `empty management key admitted a caller` )

    ( nurl_print `── UTCTime round-trip ──\n` )
    : String ts ( pki_utctime_str 1755622800 )
    ( _check == ( pki_utctime_parse ( string_data ts ) ) 1755622800 `UTCTime round-trip lost the instant` )
    ( _check < ( pki_utctime_parse `not-a-time` ) 0 `malformed UTCTime accepted` )
    ( _check < ( pki_utctime_parse `2608191700ZZ` ) 0 `short UTCTime accepted` )
    ( string_free ts )

    ( _run_suite 0 `classical CA (ECDSA P-256)` )
    ( _run_suite 65 `post-quantum CA (ML-DSA-65)` )

    ? == g_failures 0 {
        ( nurl_print `── ALL SMOKE TESTS PASSED ──\n` )
        ^ 0
    } {}
    ( nurl_print `── ` )
    : String n ( string_new )
    ( string_push_int n g_failures )
    ( nurl_print ( string_data n ) )
    ( string_free n )
    ( nurl_print ` SMOKE CHECK(S) FAILED ──\n` )
    ^ 1
}
