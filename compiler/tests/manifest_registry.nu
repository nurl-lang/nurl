// manifest_registry.nu — registry dependencies + default registry.
//
// Exercises the Phase-3 manifest extension: a path dep, a bare-string
// registry dep (default registry), an explicit-registry dep, plus the
// [package].registry default, and the dep_is_path / dep_is_registry
// discriminators.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/manifest.nu`

@ main → i {
    : s src `[package]
name = "demo"
version = "0.3.0"
registry = "https://reg.nurl-lang.org/"

[dependencies]
local = { path = "../local", version = "0.1.0" }
bare = "^1.2"
explicit = { version = "2.0", registry = "https://other.example/" }
`
    : !Manifest ManifestErr mr ( manifest_parse src `test` )
    ?? mr {
        F e → ( nurl_print ( manifest_err_name e ) )
        T m → {
            ( nurl_print `registry=` ) ( nurl_print ( string_data . m registry ) ) ( nurl_print `\n` )
            : i n ( vec_len [Dep] . m dependencies )
            ( nurl_print `deps=` ) ( nurl_println_int n )
            : ~ i k 0
            ~ < k n {
                : ?Dep dk ( vec_get [Dep] . m dependencies k )
                ?? dk {
                    T d → {
                        ( nurl_print `- ` ) ( nurl_print ( string_data . d name ) )
                        ( nurl_print ` path=` )
                        ? > ( string_len . d path ) 0 { ( nurl_print ( string_data . d path ) ) } { ( nurl_print `<none>` ) }
                        ( nurl_print ` ver=` ) ( nurl_print ( string_data . d version ) )
                        ( nurl_print ` reg=` )
                        ? > ( string_len . d registry ) 0 { ( nurl_print ( string_data . d registry ) ) } { ( nurl_print `<default>` ) }
                        ( nurl_print ? ( dep_is_path d ) ` [path]\n` ` [registry]\n` )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( manifest_free m )
        }
    }
    ( nurl_print `done\n` )
    ^ 0
}
