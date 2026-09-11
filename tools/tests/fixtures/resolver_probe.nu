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

@ fetch s registry s name → String {
    : String key ( string_from registry )
    ( string_push_str key name )
    ( nurl_eprint `FETCH ` ) ( nurl_eprintln ( string_data key ) )
    : ~ String result ( string_new )
    ?? ( json_obj_get ( graph ) `indexes` ) {
        T indexes → {
            ?? ( json_obj_get indexes ( string_data key ) ) {
                T index → { ( string_free result ) = result ( json_stringify index ) }
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
    : !( Vec LockPkg ) ResolveErr result ( resolve_registry roots `https://a.test/` \ s registry s name → String { ^ ( fetch registry name ) } )
    ( vec_free_with [Dep] roots \ Dep dep → v { ( dep_free dep ) } )
    : ~ i rc 0
    ?? result {
        T locked → {
            : String text ( lock_serialize locked )
            ( nurl_print ( string_data text ) )
            ( string_free text ) ( lockpkgs_free locked )
        }
        F error → { ( nurl_println ( resolve_err_name error ) ) = rc 1 }
    }
    ( json_free ( graph ) )
    ( nurl_free # s graph_address )
    ^ rc
}
