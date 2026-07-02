(module
  (type $p2 (func (result i32 i32)))
  (func (export "mvblock") (result i32)
    (block (type $p2) (i32.const 3) (i32.const 4))
    i32.add)
  (func (export "mvloop") (param i32) (result i32)
    ;; loop with a parameter: sum 1..n carried as a loop param pair
    (local $acc i32)
    (local $i i32)
    (local.set $i (local.get 0))
    (block $out
      (loop $l
        (br_if $out (i32.eqz (local.get $i)))
        (local.set $acc (i32.add (local.get $acc) (local.get $i)))
        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
        (br $l)))
    local.get $acc)
  (func (export "mvbr") (result i32)
    ;; br out of a 2-result block carries both values
    (block (type $p2)
      (i32.const 10) (i32.const 20)
      (br 0)
      (unreachable))
    i32.add))
