// diag_pkg_version_outside_package.nu — '( pkg_version )' reads the
// version from the nurl.toml of the package the file belongs to; a file
// with no nurl.toml above it has no version, and is told so instead of
// getting a made-up number.

@ main → i {
    ( nurl_println ( pkg_version ) )
    ^ 0
}
