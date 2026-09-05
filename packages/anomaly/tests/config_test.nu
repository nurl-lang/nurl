// config_test.nu — the configuration file, and what it layers under.
//
//   parse   — a file that is absent is fine; one that is malformed is an
//             error a caller can see, not something to shrug at.
//   read    — typed getters, with the default showing through for a key
//             that is absent or of the wrong type.
//   find    — the search order, and an explicit path winning outright.
//   layer   — the environment overlays the file only where it actually
//             says something, and `audience` derives from `client_id`.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_config_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/config.nu`
$ `src/authz.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ streq String a s b → b { ^ == ( nurl_str_eq ( string_data a ) b ) 1 }

@ write_file_str s path s body → v {
    : !v IoErr r ( write_file path body )
    ?? r { T _ → {} F _ → {} }
}

@ test_parse s dir → v {
    // Nothing there: the common case, and not an error.
    : String missing ( string_from dir )
    ( string_push_str missing `/nope.toml` )
    : AnomalyConfig c0 ( config_load ( string_data missing ) )
    ( check ! ( config_loaded c0 ) `parse: an absent file loads nothing` )
    ( check == ( nurl_str_len ( config_error c0 ) ) 0 `parse: and is not an error` )
    ( config_free c0 )
    ( string_free missing )

    // An empty path means "no file was found", not "read the cwd".
    : AnomalyConfig c1 ( config_load `` )
    ( check ! ( config_loaded c1 ) `parse: an empty path loads nothing` )
    ( config_free c1 )

    // A file somebody wrote and got wrong must be visible. Ignoring it is
    // how a service comes up unconfigured with no way to tell why.
    : String bad ( string_from dir )
    ( string_push_str bad `/bad.toml` )
    ( write_file_str ( string_data bad ) `this is = = not [[[ toml` )
    : AnomalyConfig c2 ( config_load ( string_data bad ) )
    ( check ! ( config_loaded c2 ) `parse: a malformed file does not load` )
    ( check > ( nurl_str_len ( config_error c2 ) ) 0 `parse: and reports why` )
    ( config_free c2 )
    ( string_free bad )
}

@ test_read s dir → v {
    : String p ( string_from dir )
    ( string_push_str p `/good.toml` )
    ( write_file_str ( string_data p ) `[auth]
enabled = true
issuer = "https://id.example/x/v2.0"
client_id = "cid-1"
open_ingest = false

[service]
addr = "0.0.0.0:9000"
port = 1234
` )
    : AnomalyConfig c ( config_load ( string_data p ) )
    ( check ( config_loaded c ) `read: the file loads` )
    ( check == ( nurl_str_eq ( config_path c ) ( string_data p ) ) 1 `read: it remembers where from` )

    : String iss ( config_str c `auth.issuer` `` )
    ( check ( streq iss `https://id.example/x/v2.0` ) `read: a dotted string key` )
    ( string_free iss )
    : String addr ( config_str c `service.addr` `` )
    ( check ( streq addr `0.0.0.0:9000` ) `read: a key in another table` )
    ( string_free addr )
    ( check ( config_bool c `auth.enabled` F ) `read: a true bool` )
    ( check ! ( config_bool c `auth.open_ingest` T ) `read: a false bool overrides a true default` )

    ( check ( config_has c `auth.client_id` ) `read: a present key is present` )
    ( check ! ( config_has c `auth.audience` ) `read: an absent key is absent` )

    // The default shows through for absent keys and for wrong types, so a
    // typo demotes to the default rather than to an empty string.
    : String miss ( config_str c `auth.audience` `fallback` )
    ( check ( streq miss `fallback` ) `read: an absent key yields the default` )
    ( string_free miss )
    : String wrong ( config_str c `service.port` `fallback` )
    ( check ( streq wrong `fallback` ) `read: an int read as a string yields the default` )
    ( string_free wrong )
    ( check ( config_bool c `auth.issuer` T ) `read: a string read as a bool yields the default` )
    : String nope ( config_str c `no.such.path` `fallback` )
    ( check ( streq nope `fallback` ) `read: a path through nothing yields the default` )
    ( string_free nope )
    ( config_free c )
    ( string_free p )
}

@ test_find s dir → v {
    // An explicit path wins outright, and is returned whether or not it
    // exists: a typo in --config must surface as "that file is not there",
    // not as a silent fall back to a different one.
    : String e ( config_find `/explicit/path.toml` dir )
    ( check ( streq e `/explicit/path.toml` ) `find: an explicit path wins` )
    ( string_free e )

    // Nothing explicit, nothing in the store: nothing found (unless the
    // host happens to have /etc/anomaly/anomaly.toml, which is a valid
    // answer, so only the store case is asserted).
    : String store ( string_from dir )
    ( string_push_str store `/store` )
    : !v IoErr mk ( dir_create_all ( string_data store ) )
    ?? mk { T _ → {} F _ → {} }
    : String none ( config_find `` ( string_data store ) )
    ( check ! ( streq none `/etc/anomaly/anomaly.toml` )
    `find: an empty store yields no store-local file` )
    ( string_free none )

    : String inside ( string_from ( string_data store ) )
    ( string_push_str inside `/anomaly.toml` )
    ( write_file_str ( string_data inside ) `[auth]
enabled = false
` )
    : String found ( config_find `` ( string_data store ) )
    ( check ( streq found ( string_data inside ) ) `find: <store>/anomaly.toml is found` )
    ( string_free found )
    ( string_free inside )
    ( string_free store )
}

@ test_layer s dir → v {
    : String p ( string_from dir )
    ( string_push_str p `/layer.toml` )
    ( write_file_str ( string_data p ) `[auth]
enabled = true
issuer = "https://id.example/from-file/v2.0"
client_id = "cid-from-file"
` )
    : AnomalyConfig c ( config_load ( string_data p ) )

    // The file alone.
    ( check ( anomaly_authz_apply c ) `layer: the file alone turns it on` )
    ( check == ( nurl_str_eq ( anomaly_authz_client_id ) `cid-from-file` ) 1 `layer: client id from the file` )
    // audience is derived, so a deployment never has to restate it
    ( check == ( nurl_str_eq ( anomaly_authz_audience ) `api://cid-from-file` ) 1
    `layer: audience defaults to api://<client id>` )
    // Default DENY: without a credential naming an organisation there is
    // nothing a point could belong to.
    ( check ! ( anomaly_authz_open_ingest ) `layer: open_ingest defaults to OFF` )

    // The environment overlays it.
    : !v IoErr s1 ( env_set `ANOMALY_OIDC_CLIENT_ID` `cid-from-env` )
    ?? s1 { T _ → {} F _ → {} }
    : b on2 ( anomaly_authz_apply c )
    ( check on2 `layer: still on with the environment overlaid` )
    ( check == ( nurl_str_eq ( anomaly_authz_client_id ) `cid-from-env` ) 1
    `layer: the environment overrides the file` )
    ( check == ( nurl_str_eq ( anomaly_authz_audience ) `api://cid-from-env` ) 1
    `layer: and the derived audience follows it` )

    // An unset variable must let the file show through rather than blank it.
    : !v IoErr u1 ( env_unset `ANOMALY_OIDC_CLIENT_ID` )
    ?? u1 { T _ → {} F _ → {} }
    : b on3 ( anomaly_authz_apply c )
    ( check on3 `layer: unsetting it does not turn anything off` )
    ( check == ( nurl_str_eq ( anomaly_authz_client_id ) `cid-from-file` ) 1
    `layer: an unset variable lets the file show through` )

    // The environment can also turn OFF what the file turned on.
    : !v IoErr s2 ( env_set `ANOMALY_AUTH` `0` )
    ?? s2 { T _ → {} F _ → {} }
    ( check ! ( anomaly_authz_apply c ) `layer: the environment can switch it off` )
    ( check ! ( anomaly_authz_requested c ) `layer: and that reads as "not asked for"` )
    : !v IoErr u2 ( env_unset `ANOMALY_AUTH` )
    ?? u2 { T _ → {} F _ → {} }
    ( config_free c )
    ( string_free p )

    // Asked for but unusable: on without an issuer stays off, and says so
    // differently from "nobody asked".
    : String half ( string_from dir )
    ( string_push_str half `/half.toml` )
    ( write_file_str ( string_data half ) `[auth]
enabled = true
client_id = "cid-only"
` )
    : AnomalyConfig hc ( config_load ( string_data half ) )
    ( check ! ( anomaly_authz_apply hc ) `layer: enabled without an issuer stays off` )
    ( check ( anomaly_authz_requested hc ) `layer: but it reads as "asked for"` )
    ( config_free hc )
    ( string_free half )

    // Nothing configured at all.
    : AnomalyConfig empty ( config_empty )
    ( check ! ( anomaly_authz_apply empty ) `layer: no config at all leaves it off` )
    ( check ! ( anomaly_authz_requested empty ) `layer: and nobody asked` )
    ( config_free empty )
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_config_test` )
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : !v IoErr mk ( dir_create_all ( string_data root ) )
    ?? mk { T _ → {} F _ → {} }

    ( test_parse ( string_data root ) )
    ( test_read ( string_data root ) )
    ( test_find ( string_data root ) )
    ( test_layer ( string_data root ) )

    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )
    ( nurl_print `config_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
