### Added

- `nurl-cert verify --binary <file.wasm>` now parses a WebAssembly module's import section (section id 2) and cross-checks every function import against the capability classes `N.cap` names, trusting neither `nurlc` nor the runtime source (`packages/nurl-cert/src/wasm.nu`, `packages/nurl-cert/src/verify.nu`, `docs/dev/CERTIFICATE.md`, AGORA-1038). Unknown imports, NUL bytes in import names, duplicate/out-of-order sections, and malformed binaries fail closed.
