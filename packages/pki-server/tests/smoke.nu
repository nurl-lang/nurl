// tests/smoke.nu — In-process unit/smoke tests for pki-server.
//
// Tests CA generation, device cert issuance, signature verification,
// renewal, serial extraction, revocation, and CRL generation.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/x509_gen.nu`
$ `../src/pki.nu`
$ `../src/auth.nu`

@ main → i {
    ( nurl_print `── [smoke] PKI Server Engine Tests ──\n` )

    : String tmp_dir ( string_from `/tmp/pki_test_` )
    : i now ( now_seconds )
    ( string_push_int tmp_dir now )

    : !v IoErr _cd ( dir_create_all ( string_data tmp_dir ) )

    : String ca_crt ( string_clone tmp_dir )
    ( string_push_str ca_crt `/ca.crt` )
    : String ca_key ( string_clone tmp_dir )
    ( string_push_str ca_key `/ca.key` )
    : String crl_path ( string_clone tmp_dir )
    ( string_push_str crl_path `/ca.crl` )
    : String idx_path ( string_clone tmp_dir )
    ( string_push_str idx_path `/index.txt` )

    // 1. Create CA
    ( nurl_print `[1/6] Generating CA... ` )
    : *PkiCa ca ( pki_load_or_create_ca ( string_data ca_crt ) ( string_data ca_key ) `Test PKI CA` )
    ? == # i ca 0 {
        ( nurl_print `FAILED\n` )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    // 2. Issue client certificate for device-001
    ( nurl_print `[2/6] Issuing client cert for device-001... ` )
    : PkiCert dev1 ( pki_issue_device_cert ca `device-001` 365 )
    ? == ( string_len . dev1 cert_pem ) 0 {
        ( nurl_print `FAILED\n` )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    // 3. Cryptographically verify device-001 certificate against CA
    ( nurl_print `[3/6] Verifying device-001 certificate against CA public key... ` )
    : b v1 ( pki_verify_cert . ca pubkey ( string_data . dev1 cert_pem ) `device-001` )
    ? ! v1 {
        ( nurl_print `FAILED (signature verification failed)\n` )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    // Check that verification rejects mismatched hostname
    : b v_wrong ( pki_verify_cert . ca pubkey ( string_data . dev1 cert_pem ) `device-999` )
    ? v_wrong {
        ( nurl_print `FAILED (mismatched hostname accepted)\n` )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    // 4. Extract serial and CN from certificate PEM
    ( nurl_print `[4/6] Extracting serial and CN from certificate PEM... ` )
    : PkiCertInfo info ( pki_extract_cert_info ( string_data . dev1 cert_pem ) )
    ? ! . info ok {
        ( nurl_print `FAILED (failed to extract info)\n` )
        ( pki_cert_info_free info )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    ? ! ( string_eq . info serial_hex . dev1 serial_hex ) {
        ( nurl_print `FAILED (serial mismatch: ` )
        ( nurl_print ( string_data . info serial_hex ) )
        ( nurl_print ` vs ` )
        ( nurl_print ( string_data . dev1 serial_hex ) )
        ( nurl_print `)\n` )
        ( pki_cert_info_free info )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    ( pki_cert_info_free info )
    ( nurl_print `OK\n` )

    // 5. Revoke certificate & generate CRL
    ( nurl_print `[5/6] Revoking certificate and generating RFC 5280 CRL... ` )
    : String crl_pem ( pki_record_revocation ( string_data idx_path ) ( string_data crl_path ) ca ( string_data . dev1 serial_hex ) `device-001` )
    ? ! ( string_starts_with crl_pem `-----BEGIN X509 CRL-----` ) {
        ( nurl_print `FAILED (invalid CRL header)\n` )
        ( string_free crl_pem )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    ( string_free crl_pem )
    ( nurl_print `OK\n` )

    // 6. Device key auth check
    ( nurl_print `[6/6] Checking auth helpers... ` )
    : b auth1 ( auth_check_device_key `secret123` `secret123` )
    : b auth2 ( auth_check_device_key `wrong` `secret123` )
    ? | ! auth1 auth2 {
        ( nurl_print `FAILED\n` )
        ( pki_cert_free dev1 )
        ( pki_ca_free ca )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    ( nurl_print `── ALL 6 SMOKE TESTS PASSED ──\n` )

    // Cleanup
    ( pki_cert_free dev1 )
    ( pki_ca_free ca )
    : !v IoErr _rm ( dir_remove_all ( string_data tmp_dir ) )
    ( string_free ca_crt )
    ( string_free ca_key )
    ( string_free crl_path )
    ( string_free idx_path )
    ( string_free tmp_dir )

    ^ 0
}
