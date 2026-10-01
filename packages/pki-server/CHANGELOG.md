# Changelog

## Unreleased

The ML-DSA key pair drawn for a new CA or a device certificate is an `MldsaKeys` value, not a `*MldsaKeys`: `stdlib/std/mldsa.nu` made it a self-releasing handle that its last owner drops. The two `mldsa_keys_free` calls at the end of those blocks are gone — the block's end releases the keys at the same point. No change in behaviour.

## 0.3.2

`pki_ca_free`, `pki_cert_free`, `pki_cert_info_free`, `pki_revoked_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.3.1 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
