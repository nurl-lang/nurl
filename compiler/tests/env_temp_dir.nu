// env_temp_dir.nu — where temporary files go, on each platform's own terms
// (stdlib/ext/env.nu, agora #306).
//
// POSIX reads $TMPDIR (else /tmp) and nothing else. Windows reads what
// GetTempPathW does, TMP → TEMP → USERPROFILE → SystemRoot, and NOT
// TMPDIR, which Git Bash exports as a POSIX path a native program cannot
// use. Either way the answer has no trailing separator, a root excepted.
// The six cases print the same lines on every platform; each checks that
// platform's answer.
//
// Expected output:
//   1 ok
//   2 ok
//   3 ok
//   4 ok
//   5 ok
//   6 ok

$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

@ put s name s value → v {
    ?? ( env_set name value ) { T _ → {} F _ → {} }
}

@ drop_var s name → v {
    ?? ( env_unset name ) { T _ → {} F _ → {} }
}

@ check i n s want → v {
    : String got ( env_temp_dir )
    ( nurl_print_int n )
    ? ( string_eq got ( string_from want ) ) { ( nurl_print ` ok\n` ) } {
        ( nurl_print ` FAIL: got ` ) ( nurl_print ( string_data got ) )
        ( nurl_print ` want ` ) ( nurl_print want ) ( nurl_print `\n` )
    }
}

@ main → i {
    ? == ( posix_const `PATH_LIST_SEPARATOR` ) 59 {
        ( put `TMP` `C:/nurl/t1/` ) ( put `TEMP` `C:/nurl/t2` )
        ( check 1 `C:/nurl/t1` )
        ( drop_var `TMP` )
        ( check 2 `C:/nurl/t2` )
        ( drop_var `TEMP` ) ( put `USERPROFILE` `C:/nurl/u3` )
        ( check 3 `C:/nurl/u3` )
        ( drop_var `USERPROFILE` ) ( put `SystemRoot` `C:/nurl/w4` )
        ( check 4 `C:/nurl/w4` )
        ( put `TMPDIR` `/c/nurl/msys` ) ( put `TMP` `C:/nurl/t5` )
        ( check 5 `C:/nurl/t5` )
        ( put `TMP` `C:/` )
        ( check 6 `C:/` )
    } {
        ( put `TMPDIR` `/nurl/t1/` )
        ( check 1 `/nurl/t1` )
        ( put `TMPDIR` `/` )
        ( check 2 `/` )
        ( put `TMPDIR` `` )
        ( check 3 `/tmp` )
        ( drop_var `TMPDIR` )
        ( check 4 `/tmp` )
        ( put `TMP` `/nurl/x` ) ( put `TEMP` `/nurl/w` )
        ( check 5 `/tmp` )
        ( put `TMPDIR` `/nurl/t6` )
        ( check 6 `/nurl/t6` )
    }
    ^ 0
}
