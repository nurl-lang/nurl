> [!NOTE]
> **The historical "language gotchas" list is empty as of v0.7.1+.**
> Every trap that previously needed memorisation now surfaces as a
> compiler `error:` / `warning:` with a pointing caret and the
> concrete cure inline. The remaining edge — prefix-arity strictness
> — is documented in README's **Known Limitations → Grammar**
> section, since it is a grammar property (no closing token, every
> operator has fixed arity), not a surprise the model can't predict
> from the spec. (`^` is the return operator; XOR is the distinct
> `^^` operator — see `spec/grammar.ebnf`.)
>
> Diagnostics shipped (see `compiler/nurlc.nu` for the emit sites):
>
> | Symptom                                                    | Compiler now says |
> |------------------------------------------------------------|-------------------|
> | `^ ?? v { … ^ in arms }`                                   | `error:` + `: ~ T rc … / ?? { … = rc v } / ^ rc` cure |
> | `nurl_str_len s_String` / `string_len i8*`                 | `error:` + which helper to use |
> | param named `entry`                                        | `error:` + rename suggestion |
> | `# T { ... }` where T is a struct/enum                     | `error:` + "use `@ T { ... }`" |
> | `: ~ *T` (long-loop miscompile)                            | `warning:` at decl |
> | bare `@-fn` used as a closure value                        | `error:` + `\ args → R { ( fn args ) }` wrap |
> | `?` with bare then/else followed by `{ ... }` block        | `warning:` (the n-ary `&`/`|` trap) |
> | `:`-binding shadowing a parameter                          | `warning:` |
> | closure capturing `: ~`-multi-field struct, escaping       | `warning:` (borrow-checker region escape analysis, on by default; `--no-borrowck` disables) on `^`-return / `vec_push`/`vec_insert`/`vec_set`/`thread_spawn` / assignment into a longer-lived binding |
> | `( f a )` for an `@`-fn `f` declared with a different arity | `error:` + `call to 'f' has the wrong number of arguments: expected N, got M` |
> | a prefix operator short an operand, over-reading the next line | `error:` + names the token and points back at the line whose statement is short an argument |
>
> If you are an LLM and hit a NURL compile error not listed above,
> the diagnostic itself is the source of truth — quote it verbatim
> rather than guessing. For grammar-level questions (operator arity,
> prefix notation, prefix-cascade debugging) consult
> [`../spec/grammar.ebnf`](../spec/grammar.ebnf) — it carries the
> definitive grammar including the binary-operator comment.
