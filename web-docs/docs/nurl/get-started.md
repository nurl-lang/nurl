---
outline: deep
title: Start with NURL
---

# Start with NURL <Badge type="warning" text="WIP" />

::: warning Work In Progress
NURL web documentation is maintained separately. For up-to-date information refer to the repository documentation in [docs.](https://github.com/nurl-lang/nurl/tree/main/docs)
:::

## Installing

...

## Building NURL

The only dependency needed to build NURL is clang / LLVM 15+. Install it with your desired package manager.

### 1. Build the C runtime

```bash
clang -c stdlib/runtime.c -o stdlib/runtime.o      # Linux / macOS // [!code highlight]
clang -c stdlib\runtime.c -o stdlib\runtime.o      # Windows
```

...

## Nix Flake

...
