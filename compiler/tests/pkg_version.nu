// pkg_version.nu — '( pkg_version )' is the version of the package a source
// file belongs to: the [package] table of the nearest nurl.toml above that
// file, as a string literal. The imported fixture is a package of its own,
// so its functions read ITS manifest (3.14.15, not the dependency's
// `version = "^9.9.9"`); the literal is read-only data, so binding it,
// copying it into a String and returning it from a function free nothing.

$ `stdlib/core/string.nu`
$ `compiler/tests/pkg_version_fixture/src/ver.nu`

@ main → i {
    : s v ( fixture_version )
    ( nurl_println v )
    ( nurl_println FIXTURE_VERSION )
    : String w ( string_from ( fixture_version ) )
    ( string_push_str w `-rc` )
    ( nurl_println ( string_data w ) )
    ( nurl_println_int ( nurl_str_len FIXTURE_VERSION ) )
    ^ 0
}
