# nurl-cert — memory-safety certificates for NURL programs

**Review the certificate, not the code.** `nurl-cert` turns a NURL program
into a bundle of Lean theorems about that program: it never touches memory
it does not own, and it frees everything it allocates, also when a panic
ends it. The Lean kernel checks the proofs. Anyone can check the bundle
again, without the compiler.

```sh
nurl --certify prog.nu prog            # build prog, then write prog.cert/
nurl verify prog.cert --binary prog    # check it again

nurl-cert certify prog.nu              # the same, by hand
nurl-cert certify prog.nu --profile fast
nurl-cert verify prog.cert
```

```
accepted
  M.safe proved
  M.leak proved
  term: the translator's (the translation ledger row)
```

`prog.cert/` holds:
- `Program.lean`, the program as a term of the formal model;
- `Claims.lean`, the theorems;
- `Program.core`, the compiler's core IR;
- `Elab.lean`, only when Lean proves `Cert.elab` on the standard axioms:
  the proof that the term is the one the Lean kernel builds from the core
  IR, so the translator is not trusted for it. Certify tries it for an
  accepted program whose term `elabIR` could build (numbers, raw text,
  Strings, Vecs of numbers and of raw strings, views, slices of Vecs of
  numbers, `foreach` over a Vec of numbers);
  when the proof fails, there is no Elab.lean and the bundle keeps the
  translator's ledger row;
- `manifest.json`, with:
  - each claim's status, read off `#print axioms`;
  - the program's functions;
  - the hashes of every source file, of the core and LLVM IR, and of the
    binary;
  - the toolchain versions;
  - a trust ledger of everything the claims rest on and do not prove.

The format is [`docs/dev/CERTIFICATE.md`](../../docs/dev/CERTIFICATE.md).

What the statuses mean:

| status | |
|---|---|
| `proved` | a theorem about this program, kernel-checked, the three standard axioms only |
| `validated` | decided by compiled code (`--profile fast`) |
| `assumed` | rests on a ledger row (`M.unsafe`: the compiler's `--unsafe-report`) |
| `open` | not proved: the checker refuses the program, or the translation does not cover it yet |

Fail closed:
- a program the checker refuses (exit 3) gets no proved claim;
- so does one the translation does not cover yet (exit 2), and the
  reason is in the manifest.

Today the translation covers integers, `Vec`, strings, options, structs,
closures and channels in part. Threads and globals are not covered yet.

Needs:
- `nurlc`;
- Lean's `lake` on `PATH`;
- `formal/` built (`cd formal && lake build C.Cert C.Cert3 C.Elab`).

`verify` needs only Lean.
