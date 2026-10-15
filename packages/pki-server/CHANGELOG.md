# Changelog

## [0.5.2] — 2026-10-14

Requires NURL 0.73.0 (`rand_bytes`).

### Changed

- No `unsafe` left (19 before). The CA's state is read through
  `arc_get` (nothing changes it once made: a new CA's state is built,
  its PEMs filled in, and only then shared), its random bytes come from
  the stdlib's `rand_bytes`, and the loaded CA is no longer an owning
  module global: `pki_service_init` returns it and `pki_build_app ca`
  hands it to the routes that sign, verify or publish with it.

## [0.5.1] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.5.0 does not compile under it.

### Changed

- The loaded CA is a module global that owns it (an option: none until
  `pki_service_init`), where it was an `Arc` kept as a word.

## [0.5.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.4.2 does not compile under it.

### Changed

- `PkiCa` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.4.2.
- `pki_load_or_create_ca` returns `?PkiCa`: F when the CA can be neither
  loaded nor created, where it handed back a null handle. `pki_ca_ok` is
  gone with the null handle.
- The service keeps the loaded CA as one owner behind a word made with
  `arc_into_word`, in a small `unsafe` helper (`__svc_keep_ca`);
  `pki_service_init` is safe.

## [0.4.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.4.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.4.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.4.0 does
not compile under 0.71.0.

## [0.4.0] — 2026-10-03

Nothing is released by hand any more.

### Changed (breaking)

- `PkiCa` is a handle over an rcbox instead of a `*PkiCa`: every copy is the
  same CA and the last owner releases its keys. `pki_generate_ca`,
  `pki_load_or_create_ca` and `_pki_ca_from_pem` return `PkiCa`; a load that
  fails returns a null handle, tested with the new `pki_ca_ok` (was `== 0`
  on the pointer). `pki_issue_device_cert`, `pki_issue_cert_from_csr`,
  `pki_verify_cert`, `pki_generate_crl`, `pki_record_revocation`,
  `pki_load_crl` and `pki_ca_public` take the handle. Read the CA through the
  new accessors `pki_ca_alg`, `pki_ca_cert_pem`, `pki_ca_key_pem`,
  `pki_ca_cn` instead of its fields.
- `pki_build_app` returns an `HttpApp` handle (http 0.7) instead of
  `*HttpApp`.
- Removed: `pki_ca_new` (a CA is built from its key pair in one literal) and
  the helpers `_pki_sign`, `_pki_tbs`, `_pki_wrap_cert` (now private
  `__pki_sign` / `__pki_tbs` / `__pki_wrap_cert`).
- Removed: `pki_ca_free`, `pki_cert_free`, `pki_cert_info_free` and
  `pki_revoked_free` — `PkiCert`, `PkiCertInfo` and `PkiRevoked` are plain
  values dropped with their binding (nothing outside the package called
  them).

### Changed

- The service keeps one owner of the loaded CA behind its global and each
  handler takes another for the request (an atomic count, no copy), instead
  of casting a raw address back to `*PkiCa`.
- Every `string_free` / `vec_free` / `json_free` / `x509_free` / `args_free`
  in the server and the smoke tests is gone (394 calls).
- The ML-DSA key pair drawn for a new CA or a device certificate is an
  `MldsaKeys` value (stdlib 0.69.0 made it a self-releasing handle); the
  block's end releases the keys where `mldsa_keys_free` used to. No change in
  behaviour.

### Performance

- The whole E2E workload (init, renew, JSON and form issuance, CSR signing,
  revocation, CRL, pages) runs the same instructions (±0.1 %, ECDSA nonce
  noise) and answers with the same status codes.

Requires NURL 0.69.0 and http 0.7.

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
