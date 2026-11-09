### Fixed

- **A value lent out of a binding and written in place is tied to its container** (Agora #391, #349, #461). The `:`-bound spelling of each of these was already refused, but these left views of the element alive past its end (a heap-use-after-free):
  - a holder argument written as `( vec_at vv 0 )` (or a field of one, a payload, a join of lends), for a callee that stores a view into it;
  - an element handed straight to a callee that grows or clears it, through a nested lend, a `?` join or a value block, a field of a call's result, or an accessor of your own (also in a closure);
  - a function that hands its parameter's element on to such a callee, through a nested lend or a generic function's closure parameter.

  Each is now refused as its bound twin is.
- A helper defined below its caller that returns a fresh value is no longer taken to lend every argument (Agora #349). Calls through it that were refused now run clean.

### Changed

- Refused as their bound twins are:
  - an inline holder's element cleared before the source ends, or another of its elements read;
  - a slice of the Vec read after an element grows through an inline lend;
  - a callee clearing another row of the element viewed, inline or in a generic.

### Performance

- **The compiler's accumulated lists grow by half, not word by word.** A list the compiler builds up in a symbol table was reallocated to its exact new length at every word, and wherever the allocator could not extend it in place the whole list was copied. It now takes half as much room again when it fills up. With the checks above included, dst_flagship compiles in 0.96 % fewer instructions and the compiler's own self-compile in 1.0 % fewer, with less peak memory on the self-compile. The output is byte for byte the same.
