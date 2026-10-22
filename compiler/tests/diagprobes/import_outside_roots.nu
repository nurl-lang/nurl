// Probe (not a test): an import outside the compilation's import roots.
// check_diag_coverage.sh compiles this one with NURL_IMPORT_ROOTS set to
// this directory, so /etc/hostname — present or not — is outside them.
// The behaviour itself is tested by compiler/tests/import_roots.sh.
$ `/etc/hostname`

@ main → i { ^ 0 }
