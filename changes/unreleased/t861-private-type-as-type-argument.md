### Fixed

- **A module's private type can no longer be named from another file as a
  type argument** (Agora #861). A strict module's private type was already
  refused when named bare (`: Impl x`). It was accepted inside a generic:
  `( Vec Impl )`, `( vec_new [Impl] )`, `[?Impl]`, `( Vec ( Vec Impl ) )`.
  Those spellings took the name as a single token and never checked its
  visibility, so a module could not keep a type private from code that
  wrapped it in a generic.
  - Every one of those forms is now refused with the same diagnostic as
    the bare name, at the name's own file and column.
  - Unchanged:
    - a type argument written in the module that owns the type, including
      a `pub` struct's field such as `( Shared Impl )`, read again from an
      importer;
    - a type argument inside an instance's body, already judged where the
      program wrote it.
  - Nothing in the tree relied on the old behaviour: `tools/tree_sweep.sh`
    is byte-identical.
- A generic struct template's own field types are judged against the file
  that wrote the template, once, at its first instance: a type another
  strict module keeps private is refused there (it was accepted by every
  compiler), and the module's own private types stay usable.
- A `pub` generic struct as the last declaration of an imported file no
  longer leaks its prefix onto the importer's next `$` import ("'pub' has no
  meaning on a '$' import" was reported against the importer).
