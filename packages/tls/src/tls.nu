// packages/tls/src/tls.nu — thin re-export facade.
//
// The pure-NURL TLS 1.3 client now lives in the standard library
// (`stdlib/std/tls.nu`) so that stdlib consumers — the pure HTTP client,
// psql, redis — can use it without depending on a registry package
// (stdlib cannot import `packages/`). This file stays as a backward-
// compatible shim: existing dependents that vendor `deps/tls/src/tls.nu`
// (published redis/psql) keep compiling unchanged, importing the stdlib
// implementation transitively.
$ `stdlib/std/tls.nu`
