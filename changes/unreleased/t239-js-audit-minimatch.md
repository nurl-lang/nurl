### Security

- **The JavaScript dependency audit is green again: no package pulls a
  minimatch older than 11.0.1** (Agora #239, GHSA-g3hv-75wg-m249,
  denial of service through glob-pattern amplification). The audit failed
  on every PR touching webdocs/ or tooling/vscode-nurl/.
  - The VS Code extension, where minimatch ships at run time, moves to
    vscode-languageclient 11. That needs VS Code 1.91 or newer. minimatch
    is pinned to ^11.0.1 with an `overrides` entry until the client depends
    on it itself; the client only uses `Minimatch`, whose API is unchanged.
  - webdocs drops ESLint and eslint-config-next. No workflow ran
    `pnpm lint`, and Next 16's build does not lint. Its React, import and
    a11y plugins still require minimatch 3, have no fixed release, and do
    not support ESLint 10, so the whole unused chain goes: 324 fewer
    packages in the lockfile, and no other version changed.
