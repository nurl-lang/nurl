// Registry-scoped signing keys. Trust comes from the user's configuration,
// never from a downloaded package, manifest or registry response.
//
// NURL_REGISTRY_CONFIG overrides $NURL_HOME/registries.toml (or
// ~/.nurl/registries.toml). Its [registries] table maps quoted directory URLs
// to minisign public-key payload lines. Missing default config is allowed;
// missing explicit config and malformed/ambiguous entries are errors.

$ `stdlib/ext/registry_id.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/encode.nu`

: RegistryKey { String registry String key }
: RegistryTrust { ( Vec RegistryKey ) keys }
: | RegistryTrustErr { RegistryBadConfig }

@ registry_trust_free RegistryTrust trust → v {
    ( vec_free_with [RegistryKey] . trust keys \ RegistryKey item → v {
        ( string_free . item registry ) ( string_free . item key )
    } )
}

// `registry` is a normalized URL. The returned key is borrowed from `trust`.
@ registry_trust_key RegistryTrust trust s registry → s {
    : i n ( vec_len [RegistryKey] . trust keys )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [RegistryKey] . trust keys k ) {
            T item → { ? != 0 ( nurl_str_eq ( string_data . item registry ) registry ) { ^ ( string_data . item key ) } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ ``
}

@ __trust_valid_key s key → b {
    ?? ( b64_decode_vec key ) {
        F _ → { ^ F }
        T bytes → {
            : *u data ( vec_data [u] bytes )
            : b valid & == ( vec_len [u] bytes ) 42 & == . data 0 # u 69 == . data 1 # u 100
            ( vec_free [u] bytes )
            ^ valid
        }
    }
}

// Configuration normalization is checked once before any download. Duplicate
// normalized URLs may repeat a key, but cannot silently change its meaning.
@ __trust_add RegistryTrust trust s registry s key → b {
    ? ! ( __trust_valid_key key ) { ^ F } {}
    ?? ( registry_url registry ) {
        F empty → { ( string_free empty ) ^ F }
        T normalized → {
            : s old ( registry_trust_key trust ( string_data normalized ) )
            ? > ( nurl_str_len old ) 0 {
                : b same != 0 ( nurl_str_eq old key )
                ( string_free normalized )
                ^ same
            } {}
            ( vec_push [RegistryKey] . trust keys @ RegistryKey { normalized ( string_from key ) } )
            ^ T
        }
    }
}

@ registry_trust_parse s text → !RegistryTrust RegistryTrustErr {
    : RegistryTrust trust @ RegistryTrust { ( vec_new [RegistryKey] ) }
    : ~ b ok F
    ?? ( toml_parse text ) {
        F _ → {}
        T root → {
            ?? ( toml_get root `registries` ) {
                F _ → {}
                T table → {
                    ?? table {
                        TTable entries → {
                            = ok T
                            : i n ( vec_len [TomlEntry] entries )
                            : ~ i k 0
                            ~ & ok < k n {
                                ?? ( vec_get [TomlEntry] entries k ) {
                                    T item → {
                                        ?? . item value {
                                            TStr key → { = ok ( __trust_add trust ( string_data . item key ) ( string_data key ) ) }
                                            _ → { = ok F }
                                        }
                                    }
                                    F _ → { = ok F }
                                }
                                = k + k 1
                            }
                        }
                        _ → {}
                    }
                }
            }
            ( toml_value_free root )
        }
    }
    ? ok { ^ @ !RegistryTrust RegistryTrustErr { T trust } } {}
    ( registry_trust_free trust )
    ^ @ !RegistryTrust RegistryTrustErr { F RegistryBadConfig }
}

@ __trust_config_path → String {
    : String prefix ( env_var_or `NURL_HOME` `` )
    ? > ( string_len prefix ) 0 { ( string_push_str prefix `/registries.toml` ) ^ prefix } {}
    ( string_free prefix )
    : s homevar ? == ( posix_const `PATH_LIST_SEPARATOR` ) 59 `USERPROFILE` `HOME`
    : String home ( env_var_or homevar `` )
    ? > ( string_len home ) 0 { ( string_push_str home `/.nurl/registries.toml` ) } {}
    ^ home
}

@ registry_trust_load → !RegistryTrust RegistryTrustErr {
    : ~ RegistryTrust trust @ RegistryTrust { ( vec_new [RegistryKey] ) }
    : ~ String path ( env_var_or `NURL_REGISTRY_CONFIG` `` )
    : b explicit > ( string_len path ) 0
    ? ! explicit { ( string_free path ) = path ( __trust_config_path ) } {}
    : ~ b ok T
    ? > ( string_len path ) 0 {
        ?? ( read_file ( string_data path ) ) {
            T text → {
                : !RegistryTrust RegistryTrustErr result ? == ( string_len text ) ( nurl_str_len ( string_data text ) )
                ( registry_trust_parse ( string_data text ) ) @ !RegistryTrust RegistryTrustErr { F RegistryBadConfig }
                ?? result {
                    T parsed → { ( registry_trust_free trust ) = trust parsed }
                    F _ → { = ok F }
                }
                ( string_free text )
            }
            F e → { ?? e { NotFound → { = ok ! explicit } _ → { = ok F } } }
        }
    } {}
    ( string_free path )
    ? ok {
        // The legacy single-key override applies only to NURL_REGISTRY (or
        // the built-in default when that variable is absent), not every URL.
        : String override ( env_var_or `NURL_REGISTRY_PUBKEY` `` )
        ? > ( string_len override ) 0 {
            : String scope ( env_var_or `NURL_REGISTRY` ( registry_default ) )
            = ok ( __trust_add trust ( string_data scope ) ( string_data override ) )
            ( string_free scope )
        } {}
        ( string_free override )
        ? & ok == ( nurl_str_len ( registry_trust_key trust ( registry_default ) ) ) 0 {
            = ok ( __trust_add trust ( registry_default ) `RWTGgah04Ft7n6+UNxc/MKT4eMViHBo4DLgKryJVbv9ZwedeQWpmmPq5` )
        } {}
    } {}
    ? ok { ^ @ !RegistryTrust RegistryTrustErr { T trust } } {}
    ( registry_trust_free trust )
    ^ @ !RegistryTrust RegistryTrustErr { F RegistryBadConfig }
}
