// pki-server/src/main.nu — Pure-NURL Private PKI Server.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http_router.nu`
$ `service.nu`

// Helper: env var or default
@ _env_or s name s default_val → String {
    : ?String ev ( env_get name )
    ?? ev {
        T v → { ^ v }
        F _ → { ^ ( string_from default_val ) }
    }
}

// CLI flag beats environment variable beats built-in default.
@ _resolve ArgParser ap s flag s env_name s fallback → String {
    : ~ String out ( _env_or env_name fallback )
    ?? ( args_value ap flag ) {
        T v → { ( string_free out ) = out v }
        F _ → {}
    }
    ^ out
}

// The two placeholder secrets earlier releases shipped as defaults. A
// deployment that never overrode them was authenticating every caller
// against a string printed in the README, so they are treated as "no
// key given" rather than as a key.
@ _is_placeholder_key String k → b {
    ? == ( string_len k ) 0 { ^ T } {}
    ? == 0 ( nurl_str_cmp ( string_data k ) `your-device-init-key` ) { ^ T } {}
    ? == 0 ( nurl_str_cmp ( string_data k ) `your-management-key-here` ) { ^ T } {}
    ^ F
}

// Mint a 192-bit key and tell the operator what it is — once, on
// stderr. Refusing to start would be the other defensible answer, but
// it breaks `docker run` with no volume; a key nobody can guess, printed
// where the logs will keep it, is secure without being unusable.
@ _generate_key s label → String {
    : ( Vec u ) raw ( _pki_rand_bytes 24 )
    : String hex ( _pki_bytes_to_hex raw )
    ( vec_free [u] raw )
    ( nurl_eprint `[pki-server] WARNING: no ` )
    ( nurl_eprint label )
    ( nurl_eprint ` configured — generated one for this run:\n[pki-server]   ` )
    ( nurl_eprint ( string_data hex ) )
    ( nurl_eprint `\n[pki-server] Set it explicitly to keep it across restarts.\n` )
    ^ hex
}

@ main → i {
    : ArgParser ap ( args_new `pki-server` `Pure-NURL Private PKI Server & CA` )
    ( args_opt ap `port` 112 `PORT` `listen port (default: 8080 or $PORT)` )
    ( args_opt ap `host` 104 `HOST` `bind host (default: 0.0.0.0 or $HOST)` )
    ( args_opt ap `ca-cert` 0 `PATH` `CA certificate path (default: $CA_CERT or ./certs/ca.crt)` )
    ( args_opt ap `ca-key` 0 `PATH` `CA key path (default: $CA_KEY or ./certs/ca.key)` )
    ( args_opt ap `crl-file` 0 `PATH` `CRL file path (default: $CRL_FILE or ./certs/ca.crl)` )
    ( args_opt ap `index-file` 0 `PATH` `index.txt path (default: $INDEX_FILE or ./certs/index.txt)` )
    ( args_opt ap `serial-file` 0 `PATH` `accepted and ignored; serials are 96-bit CSPRNG values` )
    ( args_opt ap `initial-dir` 0 `DIR` `initial certs dir (default: $INITIAL_CERTS_DIR or ./certs/initial)` )
    ( args_opt ap `certs-dir` 0 `DIR` `device certs dir (default: $DEVICE_CERTS_DIR or ./certs/certificates)` )
    ( args_opt ap `init-key` 0 `KEY` `device initialization key (default: $DEVICE_INIT_KEY; generated if unset)` )
    ( args_opt ap `mgmt-key` 0 `KEY` `management API key (default: $MANAGEMENT_KEY; generated if unset)` )
    ( args_opt ap `ca-cn` 0 `CN` `CA common name (default: $PKI_FQDN or "Private PKI CA")` )
    ( args_opt ap `algorithm` 0 `ALG` `CA signature algorithm for a NEW CA: p256 (default), mldsa44, mldsa65, mldsa87` )
    ( args_flag ap `help` 0 `show this help` )

    ? ( args_parse_argv ap ) {} {
        ( nurl_eprintln ( args_error ap ) )
        ( args_free ap )
        ^ 2
    }

    ? ( args_present ap `help` ) {
        : String u ( args_usage ap )
        ( nurl_print ( string_data u ) )
        ( string_free u )
        ( args_free ap )
        ^ 0
    } {}

    // 1. Resolve configuration from CLI args or ENV vars
    : String s_port ( _resolve ap `port` `PORT` `8080` )
    : ~ i port 8080
    ?? ( string_to_int s_port ) { T v → { = port v } F _ → {} }
    ( string_free s_port )

    : String s_host ( _resolve ap `host` `HOST` `0.0.0.0` )
    : String ca_cert ( _resolve ap `ca-cert` `CA_CERT` `./certs/ca.crt` )
    : String ca_key ( _resolve ap `ca-key` `CA_KEY` `./certs/ca.key` )
    : String crl_file ( _resolve ap `crl-file` `CRL_FILE` `./certs/ca.crl` )
    : String index_file ( _resolve ap `index-file` `INDEX_FILE` `./certs/index.txt` )
    : String initial_dir ( _resolve ap `initial-dir` `INITIAL_CERTS_DIR` `./certs/initial` )
    : String certs_dir ( _resolve ap `certs-dir` `DEVICE_CERTS_DIR` `./certs/certificates` )
    : String ca_cn ( _resolve ap `ca-cn` `PKI_FQDN` `Private PKI CA` )

    : String s_alg ( _resolve ap `algorithm` `PKI_ALGORITHM` `p256` )
    : i alg ( pki_alg_from_name ( string_data s_alg ) )
    ? < alg 0 {
        ( nurl_eprint `[pki-server] ERROR: unknown --algorithm '` )
        ( nurl_eprint ( string_data s_alg ) )
        ( nurl_eprintln `' (expected p256, mldsa44, mldsa65 or mldsa87)` )
        ( string_free s_alg )
        ( args_free ap )
        ^ 2
    } {}
    ( string_free s_alg )

    : ~ String init_key ( _resolve ap `init-key` `DEVICE_INIT_KEY` `` )
    ? ( _is_placeholder_key init_key ) {
        ( string_free init_key )
        = init_key ( _generate_key `device initialization key` )
    } {}

    : ~ String mgmt_key ( _resolve ap `mgmt-key` `MANAGEMENT_KEY` `` )
    ? ( _is_placeholder_key mgmt_key ) {
        ( string_free mgmt_key )
        = mgmt_key ( _generate_key `management API key` )
    } {}

    ( args_free ap )

    ( nurl_print `[pki-server] Initializing PKI subsystem...\n` )
    : b init_ok ( pki_service_init ( string_data ca_cert ) ( string_data ca_key ) ( string_data crl_file ) ( string_data index_file ) ( string_data initial_dir ) ( string_data certs_dir ) ( string_data init_key ) ( string_data mgmt_key ) ( string_data ca_cn ) alg )

    ? ! init_ok {
        ( nurl_eprintln `[pki-server] ERROR: could not initialize the CA.` )
        ( nurl_eprintln `[pki-server]        An existing --ca-cert/--ca-key pair that fails to load is NOT` )
        ( nurl_eprintln `[pki-server]        replaced: overwriting it would invalidate every certificate` )
        ( nurl_eprintln `[pki-server]        ever issued under it. Move the old pair aside to mint a new CA.` )
        ( string_free s_host )
        ( string_free ca_cert )
        ( string_free ca_key )
        ( string_free crl_file )
        ( string_free index_file )
        ( string_free initial_dir )
        ( string_free certs_dir )
        ( string_free init_key )
        ( string_free mgmt_key )
        ( string_free ca_cn )
        ^ 1
    } {}

    ( nurl_print `[pki-server] CA ready: ` )
    ( nurl_print ( string_data ca_cert ) )
    ( nurl_print `\n[pki-server] Signature algorithm: ` )
    ( nurl_print ( pki_alg_display ( pki_service_alg ) ) )
    ( nurl_print `\n[pki-server] Starting pure-NURL PKI HTTP Service on http://` )
    ( nurl_print ( string_data s_host ) )
    ( nurl_print `:` )
    : String s_port_disp ( string_new )
    ( string_push_int s_port_disp port )
    ( nurl_print ( string_data s_port_disp ) )
    ( string_free s_port_disp )
    ( nurl_print `\n` )

    : *HttpApp app ( pki_build_app )
    : i rc ( http_app_listen app ( string_data s_host ) port )

    ( http_app_free app )
    ( string_free s_host )
    ( string_free ca_cert )
    ( string_free ca_key )
    ( string_free crl_file )
    ( string_free index_file )
    ( string_free initial_dir )
    ( string_free certs_dir )
    ( string_free init_key )
    ( string_free mgmt_key )
    ( string_free ca_cn )

    ^ rc
}
