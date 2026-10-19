;; ADDBRIFC whose compared value dies at the branch (nwasm 3.1.3): the
;; bounds-checked little-endian u64 read NURL emits for bytes 0..7 of a
;; ( Vec u ) — x25519.nu since 0.73.0, function 97. Tier 8 gave the sum
;; `p + 7` the register the length had just been read from, so
;; `cmp len, p+7` compared the sum with itself and byte 7 read as 0.
;; Vec header at 1024 (data 2048, len 8), bytes 11..88 at 2048.
(module
  (memory 1)
  (data (i32.const 1024) "\00\08\00\00\00\00\00\00\08\00\00\00\00\00\00\00")
  (data (i32.const 2048) "\11\22\33\44\55\66\77\88")
  (func (export "ld64") (param i32 i64) (result i64)
    (local i32 i32 i32 i32 i64 i64 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32)
    i32.const 0
    local.set 2
    i32.const 0
    local.set 3
    i32.const 0
    local.set 4
    block ;; label = @1
      local.get 1
      local.get 0
      i32.const 16779632
      local.get 0
      select
      local.tee 5
      local.get 0
      i32.const 0
      i32.ne
      i32.const 3
      i32.shl
      i32.add
      i64.load
      local.tee 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 1
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 4
      i32.const 1
      local.set 3
    end
    i32.const 0
    local.set 0
    block ;; label = @1
      local.get 1
      i64.const 1
      i64.add
      local.tee 7
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 7
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 0
      i32.const 1
      local.set 2
    end
    i32.const 0
    local.set 8
    i32.const 0
    local.set 9
    i32.const 0
    local.set 10
    block ;; label = @1
      local.get 1
      i64.const 2
      i64.add
      local.tee 7
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 7
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 10
      i32.const 1
      local.set 9
    end
    i32.const 0
    local.set 11
    block ;; label = @1
      local.get 1
      i64.const 3
      i64.add
      local.tee 7
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 7
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 11
      i32.const 1
      local.set 8
    end
    i32.const 0
    local.set 12
    i32.const 0
    local.set 13
    i32.const 0
    local.set 14
    block ;; label = @1
      local.get 1
      i64.const 4
      i64.add
      local.tee 7
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 7
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 14
      i32.const 1
      local.set 13
    end
    i32.const 0
    local.set 15
    block ;; label = @1
      local.get 1
      i64.const 5
      i64.add
      local.tee 7
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 7
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 15
      i32.const 1
      local.set 12
    end
    i32.const 0
    local.set 16
    i32.const 0
    local.set 17
    i32.const 0
    local.set 18
    block ;; label = @1
      local.get 1
      i64.const 6
      i64.add
      local.tee 7
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 7
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 18
      i32.const 1
      local.set 17
    end
    i32.const 0
    local.set 19
    block ;; label = @1
      local.get 1
      i64.const 7
      i64.add
      local.tee 1
      local.get 6
      i64.ge_u
      br_if 0 (;@1;)
      local.get 5
      i32.load
      local.get 1
      i32.wrap_i64
      i32.add
      i32.load8_u
      local.set 19
      i32.const 1
      local.set 16
    end
    local.get 0
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 8
    i64.shl
    i64.const 0
    local.get 2
    i32.const 1
    i32.and
    select
    local.get 4
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 0
    local.get 3
    i32.const 1
    i32.and
    select
    i64.or
    local.get 10
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 16
    i64.shl
    i64.const 0
    local.get 9
    i32.const 1
    i32.and
    select
    i64.or
    local.get 11
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 24
    i64.shl
    i64.const 0
    local.get 8
    i32.const 1
    i32.and
    select
    i64.or
    local.get 14
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 32
    i64.shl
    i64.const 0
    local.get 13
    i32.const 1
    i32.and
    select
    i64.or
    local.get 15
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 40
    i64.shl
    i64.const 0
    local.get 12
    i32.const 1
    i32.and
    select
    i64.or
    local.get 18
    i64.extend_i32_u
    i64.const 255
    i64.and
    i64.const 48
    i64.shl
    i64.const 0
    local.get 17
    i32.const 1
    i32.and
    select
    i64.or
    local.get 19
    i64.extend_i32_u
    i64.const 56
    i64.shl
    i64.const 0
    local.get 16
    i32.const 1
    i32.and
    select
    i64.or
  )
)
