# Changelog

## 0.4.3

`reg_name_valid` moved to the standard library.

The package name rule — `^[a-z0-9][a-z0-9_-]{0,63}$` — is now
`stdlib/ext/registry_id.nu`, so the registry service and `nurlpkg` apply one
copy of it rather than two that can drift. The check itself is unchanged.
This landed with the toolchain's ownership hardening (#1107) and the package
was never republished, so the registry has been serving 0.4.2 with different
source ever since.
