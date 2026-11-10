### Fixed

- **A join of cursors bound to a name is a cursor too** (Agora #599). With
  `: ~ ( Vec String ) cur t`, growing through `: c ? k cur other` — or a
  `??` join, block arms, or `? k cur t` — inside `~ x t { … }` moved `t`'s
  buffer under the loop (heap use after free), where the inline join
  argument was refused. The binding is now a copy of the handle of
  whichever arm ran. A join of cursors of another container is unaffected.
