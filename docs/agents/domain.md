# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout: multi-context

This repo holds two kinds of context:

- **The language and toolchain**: `compiler/`, `stdlib/`, `tools/`, `formal/`. Its glossary is `docs/GLOSSARY.md`; its decisions are `docs/adr/`.
- **Each package** under `packages/<pkg>/` (`anomaly`, `whisper`, `nurldb`, `nwasm`, …): its own `packages/<pkg>/GLOSSARY.md` and `packages/<pkg>/docs/adr/`. A package's vocabulary (an anomaly model's versions and margins, a whisper endpointer's drafts) does not belong in the language glossary.

`GLOSSARY-MAP.md` at the repo root lists every context that has a glossary.

## Before exploring, read these

- **`GLOSSARY-MAP.md`** at the repo root: it points at one `GLOSSARY.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. For a package, also check `packages/<pkg>/docs/adr/`.

The language context's vocabulary already lives in `docs/spec.md`, `docs/MEMORY.md` and `formal/` (`CLAIM.md`, `RULES.md`). A glossary entry points there rather than restating it.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── GLOSSARY-MAP.md
├── docs/
│   ├── GLOSSARY.md                    ← language and toolchain
│   └── adr/                           ← language-wide decisions
└── packages/
    ├── anomaly/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← package-specific decisions
    └── whisper/
        ├── GLOSSARY.md
        └── docs/adr/
```

## Package docs ship with the package

Everything under `packages/<pkg>/` goes into the published tarball except `deps/`, build output, VCS files and what the package's own `.gitignore` names (`stdlib/ext/pkg_publish.nu`). A new `GLOSSARY.md` or ADR in a package therefore changes the package's bytes, and the next publish of that package needs a version bump.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the relevant `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
