// Same names in distinct registries have independent constraints and caches.
$ `stdlib/ext/resolver.nu`
$ `stdlib/ext/lockfile.nu`

: ~ i calls_a 0
: ~ i calls_b 0

@ index_text s registry s name → String {
    : b a != 0 ( nurl_str_eq registry `https://a.test/` )
    ? a { = calls_a + calls_a 1 } { = calls_b + calls_b 1 }
    ? != 0 ( nurl_str_eq name `foo` ) {
        ? a {
            ^ ( string_from `{"name":"foo","versions":[{"version":"1.0.0","checksum":"afoo","deps":[{"name":"bar","req":"^1"}]}]}` )
        } {
            ^ ( string_from `{"name":"foo","versions":[{"version":"2.0.0","checksum":"bfoo","deps":[{"name":"bar","req":"^2"}]}]}` )
        }
    } {}
    ? a {
        ^ ( string_from `{"name":"bar","versions":[{"version":"1.2.0","checksum":"abar","deps":[]}]}` )
    } {
        ^ ( string_from `{"name":"bar","versions":[{"version":"2.3.0","checksum":"bbar","deps":[]}]}` )
    }
}

@ fetch s registry s name → !RegIndex RegistryFetchErr {
    : String text ( index_text registry name )
    : !RegIndex RegistryFetchErr result ( registry_index_decode name text )
    ( string_free text ) ^ result
}

@ root s registry s req → Dep {
    ^ @ Dep { ( string_from `foo` ) ( string_new ) ( string_from req ) ( string_from registry ) }
}

@ run b reverse → String {
    : ( Vec Dep ) roots ( vec_new [Dep] )
    ? reverse {
        ( vec_push [Dep] roots ( root `https://b.test/` `^2` ) )
        ( vec_push [Dep] roots ( root `HTTPS://A.TEST:443` `^1` ) )
    } {
        ( vec_push [Dep] roots ( root `https://a.test` `^1` ) )
        ( vec_push [Dep] roots ( root `https://b.test/` `^2` ) )
    }
    : !( Vec LockPkg ) ResolveErr result ( resolve_registry roots `https://unused.test/` \ s reg s name → !RegIndex RegistryFetchErr { ^ ( fetch reg name ) } )
    ( vec_free_with [Dep] roots \ Dep d → v { ( dep_free d ) } )
    ?? result {
        F e → { ( nurl_println ( resolve_err_name e ) ) ( resolve_err_free e ) ^ ( string_new ) }
        T locked → {
            : String text ( lock_serialize locked )
            ( lockpkgs_free locked )
            ^ text
        }
    }
}

@ main → i {
    : String a ( run F )
    : String b ( run T )
    ( nurl_print ( string_data a ) )
    : b same != 0 ( nurl_str_eq ( string_data a ) ( string_data b ) )
    ( nurl_print `same=` ) ( nurl_println_int ? same 1 0 )
    ( nurl_print `fetch-a=` ) ( nurl_println_int calls_a )
    ( nurl_print `fetch-b=` ) ( nurl_println_int calls_b )
    ( string_free a ) ( string_free b )
    ? & same & == calls_a 4 == calls_b 4 { ^ 0 } { ^ 1 }
}
