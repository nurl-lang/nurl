# Changelog

## Unreleased

Nothing is released by hand any more.

- `PkiCa` is a handle over an rcbox instead of a `*PkiCa`: every copy is the
  same CA and the last owner releases its keys. `pki_generate_ca`,
  `pki_load_or_create_ca` and `_pki_ca_from_pem` return `PkiCa`; a load that
  fails returns a null handle, tested with the new `pki_ca_ok` (was `== 0`
  on the pointer). New read accessors `pki_ca_alg`, `pki_ca_cert_pem`,
  `pki_ca_key_pem`, `pki_ca_cn`. A CA is built from its key pair in one
  literal instead of filled field by field through the pointer; the signing
  helpers are private (`__pki_sign`, `__pki_tbs`, `__pki_wrap_cert`) and
  keep taking the state pointer.
- The service keeps one owner of the loaded CA behind its global and each
  handler takes another for the request (an atomic count, no copy), instead
  of casting a raw address back to `*PkiCa`.
- `PkiCert`, `PkiCertInfo` and `PkiRevoked` are plain values: `pki_ca_free`,
  `pki_cert_free`, `pki_cert_info_free` and `pki_revoked_free` are deleted
  (nothing outside the package called them), and so is every `string_free` /
  `vec_free` / `json_free` / `x509_free` / `args_free` in the server and the
  smoke tests (394 calls).
- The whole E2E workload (init, renew, JSON and form issuance, CSR signing,
  revocation, CRL, pages) runs the same instructions (±0.1 %, ECDSA nonce
  noise) and answers with the same status codes.

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
