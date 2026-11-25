### Added

- **Memory-safety certificates of programs: `nurl --certify` and `nurl verify`** (AGORA-1019). `nurl --certify prog.nu prog` builds `prog` as before, then writes `prog.cert/`.
  - The bundle's `Claims.lean` holds two theorems about the program's own term in `formal/A2`, each checked by the Lean kernel with only the three standard axioms (`propext`, `Classical.choice`, `Quot.sound`):
    - `M.safe`: no run ever gets stuck;
    - `M.leak`: every allocation is freed, also when a panic ends the run.
  - The verified checker's verdict is decided by `decide +kernel`. The claims follow from it by the new `formal/C/Cert.lean` (C13: `C.certOK2B`, `cert_safe`, `cert_leak_end`, `cert_leak_panic`).
  - `manifest.json` carries:
    - each claim's status (`proved`, `validated`, `assumed`, `open`), read off `#print axioms` and never written down;
    - the program's functions;
    - sha256 of every source file read, of the core IR, the LLVM IR and the binary;
    - the nurlc version, the `formal/` tree hash and the Lean toolchain;
    - a trust ledger: the kernel, the translation, the library, LLVM, the runtime, and each line of `--unsafe-report`.
  - `nurl verify prog.cert --binary prog` checks a bundle again without the compiler: every hash, the claims' template byte for byte, `Program.lean` held to the program grammar, the proofs and their axioms, and each status. It fails, naming the check, when a source byte, a claim's status, a theorem's statement, a `sorry`, an added axiom or the binary was tampered with.
  - `verify --rebuild` also runs nurlc and the translator again, and compares Program.core and Program.lean byte for byte. That catches the one swap a plain verify cannot see: another program's term with every hash updated.
  - A program the checker refuses, or the translation does not cover yet, gets no proved claim.
  - All 34 accepted programs of `tools/ncore/certify/` are certified, and all 24 refused ones yield no proved claim.
  - The tool is the new package **`nurl-cert` 0.1.0**, written in NURL. The format is in `docs/dev/CERTIFICATE.md`, with `docs/dev/certificate.schema.json`. CI's `certify` workflow runs it end to end.
  - The flag and subcommand names are working names until 1.0.
- **`nurlc --list-sources`** names each source file a compile reads, once, on stderr as `source <real path>`. A certificate hashes them. Without the flag, nurlc's output and cost are unchanged: 2120 programs compile byte-identical, and the self-compile is +0.004 % instructions (the flag's test) with the same peak RSS. A source path holding a newline stops the listing, rather than splitting into two records.
