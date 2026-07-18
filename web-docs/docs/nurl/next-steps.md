---
outline: deep
title: Next steps
order: 4
---

## Learn the language

- **[Language Guide]()** - prefix syntax, types, control flow, structs & enums, pattern matching,
  memory & ownership, error handling, closures, concurrency.
- **[Standard Library tour]()** - collections, strings, JSON, HTTP, crypto,
  channels, and more.
- **[examples](https://github.com/nurl-lang/nurl/tree/main/examples)** in
  the repository, runnable `.nu` programs from FizzBuzz to an HTTP
  server to a Game Boy emulator. `examples/README.md` tags each one with
  where it can run (the browser playground, or locally only).

## Try without installing anything

The [online playground](https://play.nurl-lang.org/) compiles and runs NURL
in your browser via WebAssembly. Good for testing a snippet or using on a machine you haven't set NURL up on yet.

## When something goes wrong

NURL treats compiler errors as the primary way to learn what's allowed. Every diagnostic names the problem and the fix. If you hit an error you don't understand, read it fully before
searching elsewhere, it's designed to be the answer.

For anything the compiler itself can't catch, or model-level questions like
"what exactly does the borrow checker check," the two normative references
are:

- [`docs/spec.md`](https://github.com/nurl-lang/nurl/blob/main/docs/spec.md) — the language reference.
- [`docs/MEMORY.md`](https://github.com/nurl-lang/nurl/blob/main/docs/MEMORY.md) — the memory model and borrow checker, in depth.

## Get involved

NURL is pre-1.0 and developed in the open at
[github.com/nurl-lang/nurl](https://github.com/nurl-lang/nurl). The
[roadmap](https://github.com/nurl-lang/nurl/blob/main/ROADMAP.md) tracks
what's shipped and what's next; [`CONTRIBUTING.md`](https://github.com/nurl-lang/nurl/blob/main/CONTRIBUTING.md)
covers how to contribute to the compiler and standard library, and this
site's own [contribution guide](/web-documentation/contribute.md) covers the
web documentation specifically.
