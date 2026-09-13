$ `stdlib/ext/manifest.nu`

@ expect_error s path ManifestErr expected → v {
    ?? ( manifest_load path ) {
        T manifest → { ( manifest_free manifest ) ( nurl_panic `manifest must fail` ) }
        F error → { ? != # i error # i expected { ( nurl_panic `wrong manifest error` ) } {} }
    }
}

@ exercise → !v IoErr {
    : String directory \ ( fs_tempdir `.` `.nurl-manifest-load-` )
    ; { ( string_free directory ) }
    ; { ?? ( dir_remove_all ( string_data directory ) ) { T _ → {} F _ → {} } }
    : String path ( path_join ( string_data directory ) `nurl.toml` )
    ; { ( string_free path ) }
    ( expect_error ( string_data path ) ManifestReadFailed )
    ( expect_error ( string_data directory ) ManifestReadFailed )
    \ ( write_file ( string_data path ) `` )
    ( expect_error ( string_data path ) ManifestReadFailed )
    \ ( write_file ( string_data path ) `invalid TOML` )
    ( expect_error ( string_data path ) ManifestParseFailed )
    : String valid ( string_from `[package]\nname="recover"\nversion="1.0.0"\n` )
    ; { ( string_free valid ) }
    : String nul ( string_clone valid )
    ( string_push_char nul 0 )
    ( string_push_str nul `hidden invalid content` )
    : !v IoErr written ( write_file_bytes ( string_data path ) @ ( Vec u ) { . nul ctl } )
    ( string_free nul )
    \ written
    ( expect_error ( string_data path ) ManifestParseFailed )
    \ ( write_file ( string_data path ) ( string_data valid ) )
    ?? ( manifest_load ( string_data path ) ) {
        T manifest → { ( manifest_free manifest ) }
        F _ → { ( nurl_panic `valid manifest after recoverable errors` ) }
    }
    ^ @ !v IoErr { T 0 }
}

@ main → i {
    ?? ( exercise ) {
        T _ → { ( nurl_println `manifest load errors: ok` ) ^ 0 }
        F error → { ( nurl_eprintln ( io_err_msg error ) ) ^ 1 }
    }
}
