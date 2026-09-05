// anomaly/config.nu — the configuration file.
//
// Everything the service can be told is settable three ways, and they layer
// in one fixed order:
//
//     command-line flag  >  environment variable  >  config file  >  default
//
// The file is the persistent baseline a deployment writes once; the
// environment is what a container or a unit file overrides for one run; a
// flag is what a person types to override both. Nothing here reads the
// environment or the command line — main.nu owns that layering, so the
// precedence lives in one place instead of being re-decided per setting.
//
// The file is TOML, because that is already the project's format:
//
//     [auth]
//     enabled     = true
//     issuer      = "https://login.microsoftonline.com/<tenant>/v2.0"
//     client_id   = "<application (client) id>"
//     audience    = "api://<application (client) id>"   # optional
//     open_ingest = true
//
//     [service]
//     addr    = "0.0.0.0:8811"
//     webroot = "/usr/share/anomaly/static"
//
// Deliberately NOT settable here: the store directory. The file is looked
// for inside the store, so a `store` key would be a file relocating the
// directory it was just found in — a loop with no honest answer. It stays
// `--store` / `$ANOMALY_HOME`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/toml.nu`

: AnomalyConfig {
    b loaded
    String cpath  // where it came from; empty when nothing was loaded
    String cerr  // parse failure text; empty when fine
    TomlValue root
}

@ config_empty → AnomalyConfig {
    ^ @ AnomalyConfig { F ( string_new ) ( string_new ) # TomlValue TBool }
}

@ config_free AnomalyConfig c → v {
    ( string_free . c cpath )
    ( string_free . c cerr )
    ? . c loaded { ( toml_value_free . c root ) } {}
}

// Read and parse `path`. A file that does not exist is not an error — the
// common case is having none — but a file that exists and does not parse
// IS one: silently ignoring a config file someone wrote is how a service
// comes up unconfigured and nobody can see why.
@ config_load s path → AnomalyConfig {
    ? > ( nurl_str_len path ) 0 {} { ^ ( config_empty ) }
    : !String IoErr r ( read_file path )
    ?? r {
        F _ → { ^ ( config_empty ) }
        T txt → {
            : !TomlValue TomlErr pr ( toml_parse ( string_data txt ) )
            ( string_free txt )
            ?? pr {
                T v → {
                    ^ @ AnomalyConfig { T ( string_from path ) ( string_new ) v }
                }
                F e → {
                    : String msg ( string_from path )
                    ( string_push_str msg `: ` )
                    ( string_push_str msg ( toml_err_name e ) )
                    ^ @ AnomalyConfig { F ( string_from path ) msg # TomlValue TBool }
                }
            }
        }
    }
}

@ config_loaded AnomalyConfig c → b { ^ . c loaded }

@ config_path AnomalyConfig c → s { ^ ( string_data . c cpath ) }

@ config_error AnomalyConfig c → s { ^ ( string_data . c cerr ) }

// Is the dotted key present at all? The difference between "absent" and
// "set to empty" is what lets a lower layer show through.
@ config_has AnomalyConfig c s key → b {
    ? . c loaded {} { ^ F }
    ?? ( toml_get_path . c root key ) { T _ → { ^ T } F _ → { ^ F } }
}

@ config_str AnomalyConfig c s key s dflt → String {
    ? . c loaded {} { ^ ( string_from dflt ) }
    ?? ( toml_get_path . c root key ) {
        T v → {
            ?? ( toml_as_str v ) {
                T s2 → { ^ s2 }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ ( string_from dflt )
}

@ config_bool AnomalyConfig c s key b dflt → b {
    ? . c loaded {} { ^ dflt }
    ?? ( toml_get_path . c root key ) {
        T v → {
            ?? ( toml_as_bool v ) {
                T b2 → { ^ b2 }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ dflt
}

// A string array, joined with commas — the form a global can hold. An
// absent key, a non-array, or an array with a non-string in it all yield
// the default, so a mistyped list demotes to it rather than to a
// half-read one.
@ config_str_list AnomalyConfig c s key s dflt → String {
    ? . c loaded {} { ^ ( string_from dflt ) }
    ?? ( toml_get_path . c root key ) {
        T v → {
            ?? v {
                TArr items → {
                    : String out ( string_new )
                    : i n ( vec_len [TomlValue] items )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [TomlValue] items k ) {
                            T e → {
                                ?? ( toml_as_str e ) {
                                    T sv → {
                                        ? > ( string_len out ) 0 { ( string_push_char out 44 ) } {}
                                        ( string_push_str out ( string_data sv ) )
                                        ( string_free sv )
                                    }
                                    F _ → {
                                        ( string_free out )
                                        ^ ( string_from dflt )
                                    }
                                }
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ^ out
                }
                _ → {}
            }
        }
        F _ → {}
    }
    ^ ( string_from dflt )
}

// Where the configuration file is looked for, in order:
//
//   1. `explicit`      — --config FILE, or $ANOMALY_CONFIG
//   2. <store>/anomaly.toml
//   3. /etc/anomaly/anomaly.toml
//
// An explicit path is returned whether or not it exists, so a typo in
// --config surfaces as "that file does not parse / is not there" rather
// than as the service quietly falling back to a different file.
@ config_find s explicit s store → String {
    ? > ( nurl_str_len explicit ) 0 { ^ ( string_from explicit ) } {}
    ? > ( nurl_str_len store ) 0 {
        : String p ( string_from store )
        ( string_push_str p `/anomaly.toml` )
        ? ( file_exists ( string_data p ) ) { ^ p } {}
        ( string_free p )
    } {}
    : String etc ( string_from `/etc/anomaly/anomaly.toml` )
    ? ( file_exists ( string_data etc ) ) { ^ etc } {}
    ( string_free etc )
    ^ ( string_new )
}
