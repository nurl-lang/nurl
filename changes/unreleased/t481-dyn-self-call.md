### Fixed

- **A `dyn` impl that calls its own method through a dyn field now hands back the views that call makes** (AGORA-481). With `% Lex Node { @ toks Node self String a String b … { ^ ( toks . self child b a … ) } }` beside an impl that views its first argument, the result viewed nothing, so a caller that freed the second argument read freed memory. That is refused now, and passing the arguments down in order stays accepted.
