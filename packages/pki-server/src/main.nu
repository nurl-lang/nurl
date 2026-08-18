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

@ main → i {
    : ArgParser ap ( args_new `pki-server` `Pure-NURL Private PKI Server & CA` )
    ( args_opt ap `port` 112 `PORT` `listen port (default: 8080 or $PORT)` )
    ( args_opt ap `host` 104 `HOST` `bind host (default: 0.0.0.0 or $HOST)` )
    ( args_opt ap `ca-cert` 0 `PATH` `CA certificate path (default: $CA_CERT or ./certs/ca.crt)` )
    ( args_opt ap `ca-key` 0 `PATH` `CA key path (default: $CA_KEY or ./certs/ca.key)` )
    ( args_opt ap `crl-file` 0 `PATH` `CRL file path (default: $CRL_FILE or ./certs/ca.crl)` )
    ( args_opt ap `index-file` 0 `PATH` `index.txt path (default: $INDEX_FILE or ./certs/index.txt)` )
    ( args_opt ap `serial-file` 0 `PATH` `serial file path (default: $SERIAL_FILE or ./certs/serial)` )
    ( args_opt ap `initial-dir` 0 `DIR` `initial certs dir (default: $INITIAL_CERTS_DIR or ./certs/initial)` )
    ( args_opt ap `certs-dir` 0 `DIR` `device certs dir (default: $DEVICE_CERTS_DIR or ./certs/certificates)` )
    ( args_opt ap `init-key` 0 `KEY` `device initialization key (default: $DEVICE_INIT_KEY)` )
    ( args_opt ap `mgmt-key` 0 `KEY` `management API key (default: $MANAGEMENT_KEY)` )
    ( args_opt ap `ca-cn` 0 `CN` `CA common name (default: $PKI_FQDN or "Private PKI CA")` )
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
    : ~ String s_port ( _env_or `PORT` `8080` )
    : ?String opt_port ( args_value ap `port` )
    ?? opt_port { T v → { ( string_free s_port ) = s_port v } F _ → {} }
    : ~ i port 8080
    ?? ( string_to_int s_port ) { T v → { = port v } F _ → {} }
    ( string_free s_port )

    : ~ String s_host ( _env_or `HOST` `0.0.0.0` )
    : ?String opt_host ( args_value ap `host` )
    ?? opt_host { T v → { ( string_free s_host ) = s_host v } F _ → {} }

    : ~ String ca_cert ( _env_or `CA_CERT` `./certs/ca.crt` )
    : ?String opt_ca_cert ( args_value ap `ca-cert` )
    ?? opt_ca_cert { T v → { ( string_free ca_cert ) = ca_cert v } F _ → {} }

    : ~ String ca_key ( _env_or `CA_KEY` `./certs/ca.key` )
    : ?String opt_ca_key ( args_value ap `ca-key` )
    ?? opt_ca_key { T v → { ( string_free ca_key ) = ca_key v } F _ → {} }

    : ~ String crl_file ( _env_or `CRL_FILE` `./certs/ca.crl` )
    : ?String opt_crl_file ( args_value ap `crl-file` )
    ?? opt_crl_file { T v → { ( string_free crl_file ) = crl_file v } F _ → {} }

    : ~ String index_file ( _env_or `INDEX_FILE` `./certs/index.txt` )
    : ?String opt_index_file ( args_value ap `index-file` )
    ?? opt_index_file { T v → { ( string_free index_file ) = index_file v } F _ → {} }

    : ~ String serial_file ( _env_or `SERIAL_FILE` `./certs/serial` )
    : ?String opt_serial_file ( args_value ap `serial-file` )
    ?? opt_serial_file { T v → { ( string_free serial_file ) = serial_file v } F _ → {} }

    : ~ String initial_dir ( _env_or `INITIAL_CERTS_DIR` `./certs/initial` )
    : ?String opt_initial_dir ( args_value ap `initial-dir` )
    ?? opt_initial_dir { T v → { ( string_free initial_dir ) = initial_dir v } F _ → {} }

    : ~ String certs_dir ( _env_or `DEVICE_CERTS_DIR` `./certs/certificates` )
    : ?String opt_certs_dir ( args_value ap `certs-dir` )
    ?? opt_certs_dir { T v → { ( string_free certs_dir ) = certs_dir v } F _ → {} }

    : ~ String init_key ( _env_or `DEVICE_INIT_KEY` `your-device-init-key` )
    : ?String opt_init_key ( args_value ap `init-key` )
    ?? opt_init_key { T v → { ( string_free init_key ) = init_key v } F _ → {} }

    : ~ String mgmt_key ( _env_or `MANAGEMENT_KEY` `your-management-key-here` )
    : ?String opt_mgmt_key ( args_value ap `mgmt-key` )
    ?? opt_mgmt_key { T v → { ( string_free mgmt_key ) = mgmt_key v } F _ → {} }

    : ~ String ca_cn ( _env_or `PKI_FQDN` `Private PKI CA` )
    : ?String opt_ca_cn ( args_value ap `ca-cn` )
    ?? opt_ca_cn { T v → { ( string_free ca_cn ) = ca_cn v } F _ → {} }

    ( args_free ap )

    ( nurl_print `[pki-server] Initializing PKI subsystem...\n` )
    : b init_ok ( pki_service_init ( string_data ca_cert ) ( string_data ca_key ) ( string_data crl_file ) ( string_data index_file ) ( string_data serial_file ) ( string_data initial_dir ) ( string_data certs_dir ) ( string_data init_key ) ( string_data mgmt_key ) ( string_data ca_cn ) )

    ? ! init_ok {
        ( nurl_eprintln `[pki-server] ERROR: Failed to initialize CA or PKI subsystem.` )
        ( string_free s_host )
        ( string_free ca_cert )
        ( string_free ca_key )
        ( string_free crl_file )
        ( string_free index_file )
        ( string_free serial_file )
        ( string_free initial_dir )
        ( string_free certs_dir )
        ( string_free init_key )
        ( string_free mgmt_key )
        ( string_free ca_cn )
        ^ 1
    } {}

    ( nurl_print `[pki-server] CA ready: ` )
    ( nurl_print ( string_data ca_cert ) )
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
    ( string_free serial_file )
    ( string_free initial_dir )
    ( string_free certs_dir )
    ( string_free init_key )
    ( string_free mgmt_key )
    ( string_free ca_cn )

    ^ rc
}
