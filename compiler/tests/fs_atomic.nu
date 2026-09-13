$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

@ ensure b condition s message → v {
    ? ! condition { ( nurl_panic message ) } {}
}

@ exercise → !v IoErr {
    : String directory \ ( fs_tempdir `.` `.nurl-fs-atomic-` )
    ; { ( string_free directory ) }
    ; { ?? ( dir_remove_all ( string_data directory ) ) { T _ → {} F _ → {} } }
    : String other \ ( fs_tempdir `.` `.nurl-fs-atomic-` )
    ; { ( string_free other ) }
    ; { ?? ( dir_remove_all ( string_data other ) ) { T _ → {} F _ → {} } }
    ( ensure == 0 ( nurl_str_eq ( string_data directory ) ( string_data other ) ) `unique directory names` )
    : FileStat info \ ( fs_stat ( string_data directory ) )
    ( ensure ( stat_is_dir info ) `tempdir exists before return` )
    : String os ( env_var_or `OS` `` )
    ? == 0 ( nurl_str_eq ( string_data os ) `Windows_NT` ) {
        ( ensure == ( stat_mode_bits info ) 448 `private directory permissions` )
    } {}
    ( string_free os )
    : String source ( path_join ( string_data directory ) `source` )
    ; { ( string_free source ) }
    : String dest ( path_join ( string_data directory ) `destination` )
    ; { ( string_free dest ) }
    : String missing ( path_join ( string_data directory ) `missing` )
    ; { ( string_free missing ) }
    \ ( write_file ( string_data source ) `complete replacement` )
    \ ( write_file ( string_data dest ) `previous` )
    ?? ( fs_rename ( string_data missing ) ( string_data dest ) ) {
        T _ → { ( nurl_panic `missing source must fail` ) }
        F _ → {}
    }
    : String previous \ ( read_file ( string_data dest ) )
    ( ensure != 0 ( nurl_str_eq ( string_data previous ) `previous` ) `rename failure preserves destination` )
    ( string_free previous )
    \ ( fs_rename ( string_data source ) ( string_data dest ) )
    ( ensure ! ( file_exists ( string_data source ) ) `rename consumed source` )
    : String complete \ ( read_file ( string_data dest ) )
    ( ensure != 0 ( nurl_str_eq ( string_data complete ) `complete replacement` ) `rename publishes complete contents` )
    ( string_free complete )
    \ ( fs_copy_file ( string_data dest ) ( string_data source ) )
    : String copied \ ( read_file ( string_data source ) )
    ( ensure != 0 ( nurl_str_eq ( string_data copied ) `complete replacement` ) `copy contents` )
    ( string_free copied )
    ?? ( fs_copy_file ( string_data other ) ( string_data missing ) ) {
        T _ → { ( nurl_panic `directory read must fail` ) }
        F _ → {}
    }
    ? ( file_exists `/dev/full` ) {
        ?? ( fs_copy_file ( string_data source ) `/dev/full` ) {
            T _ → { ( nurl_panic `buffered write close must fail` ) }
            F e → { ?? e { WriteFailed → {} _ → { ( nurl_panic `write failure classification` ) } } }
        }
    } {}
    ?? ( fs_tempdir ( string_data missing ) `unreachable-` ) {
        T leaked → { ( string_free leaked ) ( nurl_panic `non-directory parent must fail` ) }
        F _ → {}
    }
    ^ @ !v IoErr { T 0 }
}

@ main → i {
    ?? ( exercise ) {
        T _ → { ( nurl_println `fs atomic: ok` ) ^ 0 }
        F e → { ( nurl_eprintln ( io_err_msg e ) ) ^ 1 }
    }
}
