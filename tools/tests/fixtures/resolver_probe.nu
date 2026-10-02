// Offline resolver adapter for the independent graph oracle in test_resolver.py.
$ `stdlib/core/io.nu`
$ `stdlib/ext/resolver.nu`
$ `stdlib/ext/json.nu`

@ field Json obj s key → s {
    ?? ( json_obj_get obj key ) { T value → { ^ ( json_as_str value ) } F _ → { ^ `` } }
}

@ fetch Json graph s registry s name → !RegIndex RegistryFetchErr {
    : String key ( string_from registry )
    ( string_push_str key name )
    ( nurl_eprint `FETCH ` ) ( nurl_eprintln ( string_data key ) )
    ?? ( json_obj_get graph `errors` ) {
        T errors → { ?? ( json_obj_get errors ( string_data key ) ) {
                T value → {
                    : s kind ( json_as_str value )
                    : ~ RegistryFetchErr error @ RegistryFetchErr { RegistryTransport HttpcOther }
                    ? ( nurl_str_eq kind `503` ) { = error @ RegistryFetchErr { RegistryHttp 503 } } {}
                    ? ( nurl_str_eq kind `401` ) { = error @ RegistryFetchErr { RegistryHttp 401 } } {}
                    ? ( nurl_str_eq kind `connect` ) { = error @ RegistryFetchErr { RegistryTransport HttpcConnect } } {}
                    ? ( nurl_str_eq kind `timeout` ) { = error @ RegistryFetchErr { RegistryTransport HttpcTimeout } } {}
                    ? ( nurl_str_eq kind `tls` ) { = error @ RegistryFetchErr { RegistryTransport HttpcTls } } {}
                    ? ( nurl_str_eq kind `dns` ) { = error @ RegistryFetchErr { RegistryTransport HttpcDns } } {}
                    ? ( nurl_str_eq kind `invalid URL` ) { = error @ RegistryFetchErr { RegistryTransport HttpcInvalidUrl } } {}
                    ^ @ !RegIndex RegistryFetchErr { F error }
                }
                F _ → {}
            } }
        F _ → {}
    }
    : ~ ! RegIndex RegistryFetchErr result @ !RegIndex RegistryFetchErr { F RegistryNotFound }
    ?? ( json_obj_get graph `indexes` ) {
        T indexes → {
            ?? ( json_obj_get indexes ( string_data key ) ) {
                T index → {
                    : String text ( json_stringify index )
                    = result ( registry_index_decode name text )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ result
}

@ main → i {
    : String input ( read_all_stdin )
    : !Json JsonError parsed ( json_parse ( string_data input ) )
    : Json graph ?? parsed { T root → root F _ → { ^ 2 } }
    : ( Vec Dep ) roots ( vec_new [Dep] )
    ?? ( json_obj_get graph `roots` ) {
        T entries → {
            : i n ( json_arr_len entries )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get entries k ) {
                    T dep → { ( vec_push [Dep] roots @ Dep {
                            ( string_from ( field dep `name` ) ) ( string_new )
                            ( string_from ( field dep `req` ) ) ( string_from ( field dep `registry` ) )
                        } ) }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }
    : !( Vec LockPkg ) ResolveErr result ( resolve_registry roots `https://a.test/` \ s registry s name → !RegIndex RegistryFetchErr { ^ ( fetch graph registry name ) } )
    : ~ i rc 0
    ?? result {
        T locked → {
            : String text ( lock_serialize locked )
            ( nurl_print ( string_data text ) )
        }
        F error → {
            : String text ( resolve_err_text error )
            ( nurl_println ( string_data text ) )
            = rc 1
        }
    }
    ^ rc
}
