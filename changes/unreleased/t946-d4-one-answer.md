### Changed

- **D4 is complete: one answer per IR shape** (AGORA-946). nurlc, the
  ownership engine and the reference checker (tools/ncore) now agree on every
  shape D4 settled. The last disagreement was D4b's copy at the return: in
  `^ ( g a )`, `a` a raw string the function owns, nurlc copies what `g`
  hands back, but the core IR handed back `g`'s result itself, so a checker
  reading the IR saw a view of `a` outliving it. The IR now hands back
  `nurl_strdup` of it, which is the copy the generated code makes, and the
  engine's and the checker's tables declare it fresh. Generated code is
  unchanged. tools/ncore/RULES.md's "One IR shape, two answers" section
  becomes the rules ("D4: one answer per IR shape"), with the probes that
  hold each.
