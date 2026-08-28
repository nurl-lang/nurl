// lockfile_basic.nu — typed nurl.lock serialize + parse round-trip.
//
// Covers: deterministic sort by name, source/checksum omission for
// path/local packages, and a serialize→parse round-trip preserving every
// field.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/lockfile.nu`

@ main → i {
    : ( Vec LockPkg ) pkgs ( vec_new [LockPkg] )
    // Deliberately out of order; serialize must sort by name (alpha < zlib).
    ( vec_push [LockPkg] pkgs ( lock_pkg_new `zlib` `1.0.0` `registry+https://reg.nurl-lang.org/` `9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08` ) )
    ( vec_push [LockPkg] pkgs ( lock_pkg_new `alpha` `0.1.0` `` `` ) )

    : String text ( lock_serialize pkgs )
    ( nurl_print `── serialized ──\n` )
    ( nurl_print ( string_data text ) )

    ( nurl_print `── parsed ──\n` )
    : !( Vec LockPkg ) LockErr pr ( lock_parse ( string_data text ) )
    ?? pr {
        F e → ( nurl_print ( lock_err_name e ) )
        T got → {
            ( nurl_print `count=` ) ( nurl_println_int ( vec_len [LockPkg] got ) )
            : i n ( vec_len [LockPkg] got )
            : ~ i k 0
            ~ < k n {
                : ?LockPkg po ( vec_get [LockPkg] got k )
                ?? po {
                    T p → {
                        ( nurl_print `pkg ` ) ( nurl_print ( string_data . p name ) )
                        ( nurl_print ` v=` ) ( nurl_print ( string_data . p version ) )
                        ( nurl_print ` src=` )
                        ? > ( string_len . p source ) 0 { ( nurl_print ( string_data . p source ) ) } { ( nurl_print `<none>` ) }
                        ( nurl_print ` chk=` )
                        ? > ( string_len . p checksum ) 0 { ( nurl_print ( string_data . p checksum ) ) } { ( nurl_print `<none>` ) }
                        ( nurl_print `\n` )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( lockpkgs_free got )
        }
    }
    ( string_free text )
    ( lockpkgs_free pkgs )
    ( nurl_print `done\n` )
    ^ 0
}
