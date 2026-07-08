// manifest_basic.nu — typed-manifest parser smoke test.
//
// Two cases:
//   1. Well-formed manifest with all fields + two dependencies.
//   2. Missing-required-field case (no [package].name) → expect
//      ManifestMissingName.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/manifest.nu`

@ dump Manifest m → v {
    ( nurl_print `name=` ) ( nurl_print ( string_data . m name ) ) ( nurl_print `\n` )
    ( nurl_print `version=` ) ( nurl_print ( string_data . m version ) ) ( nurl_print `\n` )
    ( nurl_print `description=` )
    ? > ( string_len . m description ) 0 {
        ( nurl_print ( string_data . m description ) )
    } { ( nurl_print `<empty>` ) }
    ( nurl_print `\n` )
    ( nurl_print `license=` )
    ? > ( string_len . m license ) 0 {
        ( nurl_print ( string_data . m license ) )
    } { ( nurl_print `<empty>` ) }
    ( nurl_print `\n` )
    : i na ( vec_len [String] . m assets )
    ( nurl_print `assets_count=` ) ( nurl_print ( nurl_str_int na ) ) ( nurl_print `\n` )
    : ~ i ak 0
    ~ < ak na {
        : ?String ao ( vec_get [String] . m assets ak )
        ?? ao {
            T a → {
                ( nurl_print `asset[` ) ( nurl_print ( nurl_str_int ak ) ) ( nurl_print `] ` )
                ( nurl_print ( string_data a ) ) ( nurl_print `\n` )
            }
            F _ → {}
        }
        = ak + ak 1
    }
    : i n ( vec_len [Dep] . m dependencies )
    ( nurl_print `deps_count=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
    : ~ i k 0
    ~ < k n {
        : ?Dep dk ( vec_get [Dep] . m dependencies k )
        ?? dk {
            T d → {
                ( nurl_print `dep[` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `] ` )
                ( nurl_print ( string_data . d name ) )
                ( nurl_print ` path=` ) ( nurl_print ( string_data . d path ) )
                ( nurl_print ` version=` ) ( nurl_print ( string_data . d version ) )
                ( nurl_print `\n` )
            }
            F _ → {}
        }
        = k + k 1
    }
}

@ main → i {
    : s good
    `[package]
name = "demo-app"
version = "0.1.0"
description = "Demo of the manifest parser"
license = "MIT OR Apache-2.0"

[install]
assets = ["static", "web/dashboard"]

[dependencies]
http-router = { path = "../router", version = "0.2.0" }
some-lib = { path = "../some-lib" }
`

    ( nurl_print `-- good manifest --\n` )
    : !Manifest ManifestErr r ( manifest_parse good `nurl.toml` )
    ?? r {
        F e → { ( nurl_print `err=` ) ( nurl_print ( manifest_err_name e ) ) ( nurl_print `\n` ) }
        T m → {
            ( dump m )
            ( manifest_free m )
        }
    }

    ( nurl_print `\n-- missing name --\n` )
    : s bad
    `[package]
version = "0.1.0"
`
    : !Manifest ManifestErr r2 ( manifest_parse bad `bad.toml` )
    ?? r2 {
        F e → { ( nurl_print `err=` ) ( nurl_print ( manifest_err_name e ) ) ( nurl_print `\n` ) }
        T m → { ( nurl_print `unexpected ok\n` ) ( manifest_free m ) }
    }

    ^ 0
}
