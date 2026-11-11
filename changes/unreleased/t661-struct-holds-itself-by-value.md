### Fixed

- **A struct that holds itself by value is refused at its declaration,
  whatever stands in between** (Agora #661, `compiler/nurlc.nu`). Only a
  field typed as the struct itself was refused. `: N { String s ?N next }`
  or `!N i` with a use of `N` compiled and clang answered "Cannot
  allocate unsized type"; `: A { String s B b }` beside `: B { i w A a }`
  crashed the compiler (a type walk about 105 000 frames deep); a
  generic's instance in the cycle reached clang as "identified structure
  type is recursive". A declaration now asks whether one of its fields
  reaches the struct again by value — through struct fields, the parts of
  an option or a result, a generic's instance — and says which fields the
  way goes through:

  ```
  error: 'A' holds itself by value, so it has no finite size: 'A.b' has
  the type 'B', 'B.a' has the type 'A'. A value cannot contain a value of
  its own type. Put the inner one behind an owner: '( Box A )' for one
  owner, '( Rc A )' when it is shared, '( Vec A )' for several — and
  '?( Box A )' where there may be none.
  ```

  The old message for the direct case advised a raw pointer (`* Node`);
  it names the owners now. A pointer, an enum (its payloads are boxed
  when wide) and a library handle's type argument end the search, so
  `( Vec Node )`, `?( Box Node )` and an enum payload of the struct's
  type compile as before. The question is asked only of a struct with a
  field that names, by value, itself, a struct declared further down or a
  generic's instance.
