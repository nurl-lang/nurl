// Pure trust/URL controls; every owned result is released for the leak gate.
$ `stdlib/ext/registry_trust.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/registry_index.nu`

@ check_url s input s expected → b {
    ?? ( registry_url input ) {
        F empty → { ( string_free empty ) ^ == ( nurl_str_len expected ) 0 }
        T url → {
            : b same != 0 ( nurl_str_eq ( string_data url ) expected )
            ( string_free url )
            ^ same
        }
    }
}

@ check_config s input i expected → b {
    ?? ( registry_trust_parse input ) {
        F _ → { ^ == expected -1 }
        T trust → {
            : b same == ( vec_len [RegistryKey] . trust keys ) expected
            ( registry_trust_free trust )
            ^ same
        }
    }
}

@ check_index s source b expected → b {
    ?? ( regindex_parse source ) {
        F _ → { ^ ! expected }
        T index → { ( regindex_free index ) ^ expected }
    }
}

@ main → i {
    : ~ b ok T
    = ok & ok ( check_url `HTTPS://Example.COM:443/base` `https://example.com/base/` )
    = ok & ok ( check_url `http://[::1]:8912/a//` `http://[::1]:8912/a//` )
    = ok & ok ( check_url `https://u:p@host/` `` )
    = ok & ok ( check_url `https://host/?query` `` )
    = ok & ok ( check_url `https://host/#fragment` `` )
    = ok & ok ( check_url `https://host/\nother` `` )
    = ok & ok ( check_url `file:///tmp/registry` `` )
    = ok & ok ( registry_name_valid `foo-bar_12` )
    = ok & ok ! ( registry_name_valid `../escape` )
    = ok & ok ! ( registry_name_valid `-option` )
    = ok & ok ( check_config `[registries]
"HTTPS://A.TEST:443"="RWTGgah04Ft7n6+UNxc/MKT4eMViHBo4DLgKryJVbv9ZwedeQWpmmPq5"
"https://a.test/"="RWTGgah04Ft7n6+UNxc/MKT4eMViHBo4DLgKryJVbv9ZwedeQWpmmPq5"
` 1 )
    = ok & ok ( check_config `[registries]
"https://a.test/"="not-a-key"
` -1 )
    = ok & ok ( check_config `[registries]
"https://a.test/"=123
` -1 )
    = ok & ok ( check_config `[registries]
"https://a.test/"="RWTGgah04Ft7n6+UNxc/MKT4eMViHBo4DLgKryJVbv9ZwedeQWpmmPq5"
"https://a.test:443"="RWQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
` -1 )
    // Reject invalid identity fields before C-string projection; free every AST.
    = ok & ok ( check_index `{"name":"foo\\u0000other","versions":[{"version":"1.0.0","checksum":"hash","deps":[{"name":"bar","req":"^1"}]}]}` F )
    = ok & ok ( check_index `{"name":"foo","versions":[{"version":"1.0.0\\u0000other","checksum":"hash","deps":[{"name":"bar","req":"^1"}]}]}` F )
    = ok & ok ( check_index `{"name":"foo","versions":[{"version":"1.0.0","checksum":"hash\\u0000other","deps":[{"name":"bar","req":"^1"}]}]}` F )
    = ok & ok ( check_index `{"name":"foo","versions":[{"version":"1.0.0","checksum":"hash","deps":[{"name":"bar\\u0000other","req":"^1"}]}]}` F )
    = ok & ok ( check_index `{"name":"foo","versions":[{"version":"1.0.0","checksum":"hash","deps":[{"name":"bar","req":"^1\\u0000other"}]}]}` F )
    = ok & ok ( check_index `{"name":"foo","versions":{}}` F )
    = ok & ok ( check_index `{"name":"foo","versions":[{"version":"1.0.0","checksum":"hash","yanked":"false"}]}` F )
    = ok & ok ( check_index `{"name":"foo","versions":[{"version":"1.0.0","checksum":"hash"}]}` T )
    = ok & ok ( check_config `[registries]\n"https://a.test/"="AA=="\n` -1 )
    // Locks quote every string, including source paths with quotes and slashes.
    : ( Vec LockPkg ) packages ( vec_new [LockPkg] )
    ( vec_push [LockPkg] packages ( lock_pkg_new `foo` `1.0.0` `deps/quoted"path\\next` `hash` ) )
    : String text ( lock_serialize packages )
    ?? ( lock_parse ( string_data text ) ) {
        F _ → { = ok F }
        T parsed → {
            ?? ( vec_get [LockPkg] parsed 0 ) {
                F _ → { = ok F }
                T p → { = ok & ok != 0 ( nurl_str_eq ( string_data . p source ) `deps/quoted"path\\next` ) }
            }
            ( lockpkgs_free parsed )
        }
    }
    ( string_free text )
    ( lockpkgs_free packages )
    ? ok { ( nurl_println `registry trust and lock identity: ok` ) ^ 0 } { ^ 1 }
}
