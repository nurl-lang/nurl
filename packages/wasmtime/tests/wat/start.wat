(module
  (global $g (mut i32) (i32.const 0))
  (func $s (global.set $g (i32.const 99)))
  (start $s)
  (func (export "g") (result i32) (global.get $g)))
