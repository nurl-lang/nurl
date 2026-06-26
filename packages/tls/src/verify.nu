// packages/tls/src/verify.nu — thin re-export facade.
//
// The certificate-chain verifier now lives in the standard library
// (`stdlib/std/tls_verify.nu`); see tls.nu for the rationale. Kept as a
// shim so anything that imported `deps/tls/src/verify.nu` directly still
// resolves.
$ `stdlib/std/tls_verify.nu`
