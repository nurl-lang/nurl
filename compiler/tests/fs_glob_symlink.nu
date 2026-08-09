// requires: live
//
// fs_glob must descend a symlink to a directory.
//
// glob(3) resolves symbolic links in INTERMEDIATE path components; only
// the final component is matched unlinked. NURL's glob classified every
// component with `nurl_path_type`, which is lstat-based on purpose (so
// dir_remove_all can never follow a link out of the tree it was handed),
// and then demanded type 2 = directory to descend. A symlinked directory
// answers 3, so the frontier emptied and the pattern returned nothing —
// including patterns with no metacharacter in them at all.
//
// Invisible on Linux, total on macOS: /tmp there is a symlink to
// private/tmp, so every absolute pattern under it failed on its FIRST
// segment. The whole glob section of fs_glob returned empty on the macOS
// CI leg while passing everywhere else.
//
// POSIX-only: it needs an unprivileged symlink(2) and /tmp. Windows is
// skipped by name in run_tests.ps1, alongside the termios and AF_UNIX
// tests, rather than behind a `requires:` command probe — the first
// version declared `ln` on the reasoning that a host without it is a
// host without symlinks, and the Windows runner has Git for Windows on
// PATH, so `ln.exe` resolved and the test ran anyway.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`

// Print `label: <count> <basename>…`, basenames sorted so the on-disk
// order of readdir cannot reach the golden.
@ report s label s pat → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : !( Vec String ) IoErr gr ( fs_glob pat )
    ?? gr {
        T ms → {
            : i n ( vec_len [String] ms )
            : ( Vec String ) names ( vec_new [String] )
            : ~ i k 0
            ~ < k n {
                : ?String mo ( vec_get [String] ms k )
                ?? mo {
                    T m → {
                        : s full ( string_data m )
                        : i ln ( nurl_str_len full )
                        : ~ i cut 0
                        : ~ i j 0
                        ~ < j ln {
                            ? == ( nurl_str_at full ln j ) 47 { = cut + j 1 } {}
                            = j + j 1
                        }
                        : String bn ( string_with_cap + - ln cut 1 )
                        : ~ i q cut
                        ~ < q ln { ( string_push_char bn ( nurl_str_at full ln q ) ) = q + q 1 }
                        ( vec_push [String] names bn )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            : ( @ i String String ) cmp \ String a String b → i { ^ ( cmp_string a b ) }
            ( sort_by [String] names cmp )
            ( nurl_print ( nurl_str_int n ) )
            : ~ i p 0
            ~ < p ( vec_len [String] names ) {
                : ?String no ( vec_get [String] names p )
                ?? no { T x → { ( nurl_print ` ` ) ( nurl_print ( string_data x ) ) } F _ → {} }
                = p + p 1
            }
            : ~ i f 0
            ~ < f ( vec_len [String] names ) {
                : ?String no2 ( vec_get [String] names f )
                ?? no2 { T x → ( string_free x ) F _ → {} }
                = f + f 1
            }
            ( vec_free [String] names )
            : ~ i mk 0
            ~ < mk n {
                : ?String mo2 ( vec_get [String] ms mk )
                ?? mo2 { T m → ( string_free m ) F _ → {} }
                = mk + mk 1
            }
            ( vec_free [String] ms )
        }
        F _ → ( nurl_print `<err>` )
    }
    ( nurl_print `\n` )
}

@ wfj s base s name s content → v {
    : String p ( _glob_join base name )
    : !v IoErr r ( write_file ( string_data p ) content )
    ?? r { T _ → {} F _ → ( nurl_print `write FAILED\n` ) }
    ( string_free p )
}

@ main → i {
    // Root under /tmp, pid-suffixed so parallel runs cannot collide.
    : String root ( string_with_cap 64 )
    ( string_push_str root `/tmp/nurlglobsym_` )
    ( string_push_str root ( nurl_str_int ( getpid ) ) )
    : s r ( string_data root )
    : !v IoErr _rm0 ( dir_remove_all r ) ?? _rm0 { T _ → {} F _ → {} }
    : !v IoErr _mk ( dir_create r )
    ?? _mk { T _ → {} F _ → ( nurl_print `mkdir root FAILED\n` ) }

    // root/real/{a.nu,b.nu,c.txt}, root/real/sub/deep.nu, root/link -> real
    : String real ( _glob_join r `real` )
    : String sub ( _glob_join ( string_data real ) `sub` )
    : !v IoErr _m1 ( dir_create ( string_data real ) ) ?? _m1 { T _ → {} F _ → {} }
    : !v IoErr _m2 ( dir_create ( string_data sub ) ) ?? _m2 { T _ → {} F _ → {} }
    ( wfj ( string_data real ) `a.nu` `a` )
    ( wfj ( string_data real ) `b.nu` `b` )
    ( wfj ( string_data real ) `c.txt` `c` )
    ( wfj ( string_data sub ) `deep.nu` `d` )

    : String link ( _glob_join r `link` )
    : !v IoErr sl ( fs_symlink ( string_data real ) ( string_data link ) )
    ?? sl {
        T _ → ( nurl_print `symlink_created=T\n` )
        F _ → ( nurl_print `symlink_created=F\n` )
    }

    // The link really is a link — 3 is lstat's answer, and it is the
    // answer glob used to descend on. Deliberately NOT also printing
    // nurl_path_type_follow here: a test that calls the new primitive
    // fails to COMPILE when the fix is reverted, which looks like a
    // pass-to-fail either way but stops proving anything about glob.
    // What must be pinned is the behaviour below.
    ( nurl_print `lstat_type=` ) ( nurl_print ( nurl_str_int ( nurl_path_type ( string_data link ) ) ) ) ( nurl_print `\n` )

    : String p1 ( _glob_join ( string_data link ) `*.nu` )
    : String p2 ( _glob_join ( string_data link ) `a.nu` )
    : String p3 ( _glob_join ( string_data link ) `sub/*.nu` )
    : String p4 ( _glob_join ( string_data link ) `**/*.nu` )
    ( report `star` ( string_data p1 ) )
    ( report `literal` ( string_data p2 ) )
    ( report `nested` ( string_data p3 ) )
    ( report `doublestar` ( string_data p4 ) )
    ( string_free p1 ) ( string_free p2 ) ( string_free p3 ) ( string_free p4 )

    : !v IoErr _rm ( dir_remove_all r ) ?? _rm { T _ → {} F _ → {} }
    ( string_free link ) ( string_free sub ) ( string_free real ) ( string_free root )
    ^ 0
}
