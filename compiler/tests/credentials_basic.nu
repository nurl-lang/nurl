// credentials_basic.nu — ~/.nurl/credentials: where it lives, who can read
// it, and set / get / upsert / remove.
//
// The test points the platform's home variable at a fresh temporary
// directory before touching anything (HOME on POSIX, USERPROFILE on
// Windows), so it never reads or writes a real credentials file and runs
// in every corpus run. Output is identical on every platform.
//
// What it pins:
//   * env_home_dir follows the platform's own variable — on Windows a HOME
//     pointing somewhere else is ignored (it is set only by Unix-flavoured
//     shells, and reading it moved the file with the shell);
//   * the file lands under that home, never in the working directory;
//   * it is owner-only (0600) on POSIX;
//   * with no home at all, nothing is written anywhere and set / remove
//     fail with NotFound (nurlpkg login once wrote a token into a
//     checkout through a "." fallback).

$ `stdlib/ext/credentials.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`

@ ignore ! v IoErr r → v { ?? r { T _ → {} F _ → {} } }

@ check s label b ok → v {
    ( nurl_print label ) ( nurl_print ? ok `=T\n` `=F\n` )
}

@ show s label s reg → v {
    : String t ( creds_get reg )
    ( nurl_print label ) ( nurl_print `=` )
    ? > ( string_len t ) 0 { ( nurl_print ( string_data t ) ) } { ( nurl_print `<none>` ) }
    ( nurl_print `\n` )
}

@ is_windows → b { ^ == ( posix_const `PATH_LIST_SEPARATOR` ) 59 }

@ set_home s dir → v {
    ? ( is_windows ) {
        ( ignore ( env_set `USERPROFILE` dir ) )
        // a different HOME, as Git Bash would export, must not win
        ( ignore ( env_set `HOME` `C:/not-the-profile` ) )
    } { ( ignore ( env_set `HOME` dir ) ) }
}

@ clear_home → v {
    ( ignore ( env_unset `HOME` ) )
    ( ignore ( env_unset `USERPROFILE` ) )
    ( ignore ( env_unset `HOMEDRIVE` ) )
    ( ignore ( env_unset `HOMEPATH` ) )
}

@ main → i {
    : String home ?? ( fs_tempdir `` `credhome` ) {
        T d → d
        F _ → { ( nurl_print `cannot create a temporary home\n` ) ^ 1 }
    }
    : b cwd_had_creds ( file_exists `.nurl/credentials` )
    ( set_home ( string_data home ) )

    : String h ( env_home_dir )
    ( check `home_follows_platform_var` ( string_eq h home ) )
    : String want ( string_from ( string_data home ) )
    ( string_push_str want `/.nurl/credentials` )
    ( check `path_under_home` ( string_eq ( creds_path ) want ) )

    : s r1 `https://reg.a/`
    : s r2 `https://reg.b/`
    ( ignore ( creds_set r1 `tok-a1` ) )
    ( check `file_written_under_home` ( file_exists ( string_data want ) ) )
    // Owner-only from creation (POSIX mode bits; Windows applies the
    // profile's ACL, which this cannot read portably).
    : ~ b private T
    ? ! ( is_windows ) {
        ?? ( fs_stat ( string_data want ) ) {
            T st → { = private == ( stat_mode_bits st ) 384 }
            F _ → { = private F }
        }
    } {}
    ( check `file_owner_only` private )
    ( show `a` r1 )  // tok-a1
    ( ignore ( creds_set r2 `tok-b1` ) )
    ( show `a_keep` r1 )  // tok-a1 (still there after 2nd registry)
    ( show `b` r2 )  // tok-b1
    ( ignore ( creds_set r1 `tok-a2` ) )
    ( show `a_upsert` r1 )  // tok-a2 (replaced, not duplicated)
    ( show `b_keep` r2 )  // tok-b1
    ( ignore ( creds_remove r1 ) )
    ( show `a_removed` r1 )  // <none>
    ( show `b_final` r2 )  // tok-b1
    ( ignore ( creds_remove r2 ) )

    // No home at all: nowhere to keep a token — and not the cwd either.
    ( clear_home )
    ( check `no_home_is_empty` == ( string_len ( env_home_dir ) ) 0 )
    ( check `no_home_no_path` == ( string_len ( creds_path ) ) 0 )
    : b refused ?? ( creds_set r1 `tok-x` ) {
        T _ → F
        F e → ?? e { NotFound → T _ → F }
    }
    ( check `no_home_set_refused` refused )
    ( show `no_home_get` r1 )  // <none>
    ( check `cwd_untouched` == ( file_exists `.nurl/credentials` ) cwd_had_creds )

    ( ignore ( dir_remove_all ( string_data home ) ) )
    ( nurl_print `done\n` )
    ^ 0
}
