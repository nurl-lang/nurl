;; addrfold.wat — the `i32.add` that computes a load's address is folded
;; into the load (`__fuse_addr`). Every case here is one the fold must get
;; right, not just the one it fires on.
(module
  (memory 1)
  (data (i32.const 0) "\01\02\03\04\05\06\07\08")

  ;; the fold fires: the add is the record before the load and its result
  ;; is a stack slot nothing else can see
  (func (export "fused") (param i32) (result i32)
    (i32.load8_u (i32.add (local.get 0) (i32.const 3))))

  ;; the address is ALSO a local, so `local.set` retargeted the add at it
  ;; and the value outlives the access — the fold must decline
  (func (export "kept") (param i32) (result i32) (local i32)
    (local.set 1 (i32.add (local.get 0) (i32.const 3)))
    (i32.add (i32.load8_u (local.get 1)) (local.get 1)))

  ;; the add is the first record of a loop body: deleting it must leave the
  ;; loop's branch target on the access that took its place
  (func (export "loopfuse") (param i32) (result i32) (local i32) (local i32)
    (block $out
      (loop $l
        (br_if $out (i32.eq (local.get 1) (i32.const 4)))
        (local.set 2 (i32.add (local.get 2)
                              (i32.load8_u (i32.add (local.get 0) (local.get 1)))))
        (local.set 1 (i32.add (local.get 1) (i32.const 1)))
        (br $l)))
    (local.get 2))

  ;; a folded address and a memarg offset on the same access
  (func (export "off") (param i32) (result i64)
    (i64.load8_u offset=2 (i32.add (local.get 0) (i32.const 1))))

  ;; the bounds check still sees the whole address
  (func (export "oob") (param i32) (result i32)
    (i32.load8_u (i32.add (local.get 0) (i32.const 65535))))
)
