### Fixed

- **Two readers of a field no longer both free its old value** (Agora #354).
  When `. o name` is replaced, the old value goes to a binding that was read
  out of the field (#265). With two such readers (`: String g1 . o name  :
  String g2 . o name`), both took it, and both freed it where their scope
  ended. Now only the first live one takes it, the outermost in declaration
  order, and the others keep a view of it. A later reader handed to a
  `sink` or returned is still open (docs/LIMITATIONS.md).
