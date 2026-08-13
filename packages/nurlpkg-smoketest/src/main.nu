// nurlpkg-smoketest — prove a registry round-trip end to end.
//
// Publishing this package and then installing it back exercises every
// stage nurlpkg has: pack → upload → index → resolve → download →
// verify checksum → extract → build → run. It carries no dependencies
// and no generated files, so anything that goes wrong is the registry
// or the transport, never the package.

$ `stdlib/core/io.nu`

@ main → i {
    ( nurl_print `nurlpkg-smoketest 0.1.0 — registry round-trip OK\n` )
    ^ 0
}
