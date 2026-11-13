### Fixed

- **A view of a matched option's payload ends when a callee grows the payload** (Agora #816). Take `?? o { T q → … }` with a slice of `q`, then `( w o )`, where `w` matches its option parameter and grows the payload. The slice outlived the growth and read the moved buffer (heap-use-after-free). The slice now ends at the call, and so do views of a cursor over `q` and of `q`'s fields; `q` itself still reaches the payload. A callee that moves only an element's buffer ends only the views through the elements, and a callee that only reads the payload leaves the slice valid. The literal spelling, `( w @ ?( Vec u ) { T xs } )` with a slice of `xs`, is refused through Agora #799.

### Known issues

- **A matched option field still has this hole** (Agora #832): `?? . h o { T q → … ( w . h o ) … }`. Its payload is recorded as lent out of `h`, not `h.o`, so the growth through the field does not reach the slice.
- **More holes around matched payloads** (Agora #842): a view of a local option's payload handed out of its arm; one call given both the option and a view of its payload; a callee growing the payload inline through an element or an `Rc`.
