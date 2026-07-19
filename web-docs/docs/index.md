---
layout: home

hero:
  name: "NURL"
  text: "Documentation"
  tagline: All texts for the Neural Unified Representation Language
  image:
      src: /graphics/nurl1c.svg
      alt: nurl logo
  actions:
    - theme: brand
      text: Start with NURL
      link: /nurl/get-started.md
    - theme: alt
      text: Open Playground
      link: https://play.nurl-lang.org/

features:
  - title: Designed for LLMs
    icon:
      src: /icons/cpu.svg
      alt: CPU icon
      width: 24
      height: 24
      wrap: true
    details: Every operator takes a fixed number of arguments. There are no infix operators or precedence rules. Only about 50 grammar rules, NURL is simple for both humans and AI to parse.
  - title: LLVM Native Performance
    icon:
      src: /icons/zap.svg
      alt: Lightning bolt icon
      width: 24
      height: 24
      wrap: true
    details: Compile to optimized native binaries through LLVM with support for Linux, Windows, macOS, WebAssembly, ARM64, RISC-V, and embedded targets.
  - title: Deterministic Compiler
    icon:
      src: /icons/target.svg
      alt: Target icon
      width: 24
      height: 24
      wrap: true
    details: NURL's compiler is designed to produce reproducible builds. Given the same source code, compiler version, and target, you'll get identical output every time.
---