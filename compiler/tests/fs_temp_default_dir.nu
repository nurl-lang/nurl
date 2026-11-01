// fs_temp_default_dir.nu — an empty `dir` puts fs_tempdir's directory and
// fs_tempfile's file under the platform's temp directory (env_temp_dir),
// and `.` still means the current directory (agora #322).
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

@ main → i {
    : String t ( env_temp_dir )
    ?? ( fs_tempdir `` `nurl-t322-` ) {
        T d → {
            ( nurl_println ? ( string_starts_with d ( string_data t ) ) `tempdir "": under env_temp_dir` `tempdir "": ELSEWHERE` )
            ?? ( dir_remove_all ( string_data d ) ) {
                T _ → ( nurl_println `tempdir "": removed` )
                F _ → ( nurl_println `tempdir "": NOT REMOVED` )
            }
        }
        F _ → ( nurl_println `tempdir "": FAILED` )
    }
    ?? ( fs_tempfile `` `nurl-t322-` ) {
        T f → {
            ( nurl_println ? ( string_starts_with f ( string_data t ) ) `tempfile "": under env_temp_dir` `tempfile "": ELSEWHERE` )
            ( nurl_println ? ( file_exists ( string_data f ) ) `tempfile "": exists` `tempfile "": MISSING` )
            : !v IoErr _d ( file_delete ( string_data f ) )
        }
        F _ → ( nurl_println `tempfile "": FAILED` )
    }
    ?? ( fs_tempfile `.` `nurl-t322-` ) {
        T f → {
            ( nurl_println ? ( string_starts_with f `./nurl-t322-` ) `tempfile ".": in the current directory` `tempfile ".": ELSEWHERE` )
            : !v IoErr _d ( file_delete ( string_data f ) )
        }
        F _ → ( nurl_println `tempfile ".": FAILED` )
    }
    ^ 0
}
