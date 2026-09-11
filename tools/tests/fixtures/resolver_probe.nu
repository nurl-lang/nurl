// Offline resolver adapter for the independent graph oracle in test_resolver.py.
$ `stdlib/core/io.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/ext/resolver.nu`
$ `stdlib/ext/json.nu`

: ~ i graph_address 0

@ graph → Json { ^ . # *Json graph_address 0 }

@ field Json obj s key → s {
    ?? ( json_obj_get obj key ) { T value → { ^ ( json_as_str value ) } F _ → { ^ `` } }
}

@ fetch s registry s name → !RegIndex RegistryFetchErr {
    : String key ( string_from registry )
    ( string_push_str key name )
    ( nurl_eprint `FETCH ` ) ( nurl_eprintln ( string_data key ) )
    ?? ( json_obj_get ( graph ) `errors` ) {
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
                    ( string_free key ) ^ @ !RegIndex RegistryFetchErr { F error }
                }
                F _ → {}
            } }
        F _ → {}
    }
    : ~ ! RegIndex RegistryFetchErr result @ !RegIndex RegistryFetchErr { F RegistryNotFound }
    ?? ( json_obj_get ( graph ) `indexes` ) {
        T indexes → {
            ?? ( json_obj_get indexes ( string_data key ) ) {
                T index → {
                    : String text ( json_stringify index )
                    = result ( registry_index_decode name text )
                    ( string_free text )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( string_free key )
    ^ result
}

@ main → i {
    : String input ( read_all_stdin )
    : !Json JsonError parsed ( json_parse ( string_data input ) )
    ( string_free input )
    ?? parsed { F _ → { ^ 2 } T root → {
            : *Json data ( alloc [Json] 1 )
            = . data 0 root
            = graph_address # i data
        } }
    : ( Vec Dep ) roots ( vec_new [Dep] )
    ?? ( json_obj_get ( graph ) `roots` ) {
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
    : !( Vec LockPkg ) ResolveErr result ( resolve_registry roots `https://a.test/` \ s registry s name → !RegIndex RegistryFetchErr { ^ ( fetch registry name ) } )
    ( vec_free_with [Dep] roots \ Dep dep → v { ( dep_free dep ) } )
    : ~ i rc 0
    ?? result {
        T locked → {
            : String text ( lock_serialize locked )
            ( nurl_print ( string_data text ) )
            ( string_free text ) ( lockpkgs_free locked )
        }
        F error → {
            : String text ( resolve_err_text error )
            ( nurl_println ( string_data text ) ) ( string_free text )
            ( resolve_err_free error ) = rc 1
        }
    }
    ( json_free ( graph ) )
    ( nurl_free # s graph_address )
    ^ rc
}
