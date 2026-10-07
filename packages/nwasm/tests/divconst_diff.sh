#!/usr/bin/env bash
# Differential sweep of integer division and remainder by a constant: every
# div/rem opcode against ~45 divisors per width (powers of two, both signs,
# add-indicator magics, the extremes), on canonical and non-canonical i32
# operands, results read back both sign- and zero-extended, in small leaf
# functions and in one function with many values live. The checksum over
# ~600 edge-case input pairs and 3000 random ones must match the reference
# wasmtime under the register-allocating JIT, the template JIT and the
# interpreter.
#
#   tests/divconst_diff.sh <nwasm-binary>
#
# Needs: python3, wasm-tools, wasmtime.
set -u
NW=${1:?usage: divconst_diff.sh <nwasm-binary>}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 - "$WORK/d.wat" <<'PY'
import sys
c32 = [1,2,3,4,5,6,7,8,10,11,12,13,16,25,60,100,125,160,641,1000,1024,65536,1000000007,2147483647,
       -1,-2,-3,-5,-7,-8,-10,-1000,-2147483648,-2147483647,-2,-16,0x40000000,-0x40000000,0x7ffffffe,
       -0x10000000, (3<<30) - (1<<32), 1<<30, 0x55555555, -0x55555555, 1000000, 999999999, 4294967295-(1<<32), 4294967294-(1<<32)]
c64 = [1,2,3,4,5,7,10,16,100,160,1000,1<<32,(1<<32)+1,(1<<32)-1,1<<33,10**12,10**18,1<<62,(1<<62)+1,(1<<63)-1,
       -(1<<63),-(1<<62),-1,-2,-3,-7,-10,-1000,-(10**18),6700417,274177,(1<<63)+1-(1<<64),-(1<<32),0x5555555555555555,
       (1<<64)-2-(1<<64), 0xAAAAAAAAAAAAAAAA-(1<<64), 0xF000000000000000-(1<<64), 1<<40, 3, 123456789123]
c32 = list(dict.fromkeys(c32)); c64 = list(dict.fromkeys(c64))
ops32 = ['div_s','div_u','rem_s','rem_u']
out = ['(module']
funcs = []
fi = 0
def ok(op, c):
    if c == 0: return False
    if op == 'div_s' and c == -1: return False
    return True
mix = []
# separate small functions: param canonical
for c in c32:
    for op in ops32:
        if not ok(op, c): continue
        out.append(f'  (func $a{fi} (param i32 i32) (result i32) (i32.{op} (i32.add (local.get 0) (local.get 1)) (i32.const {c})))')
        mix.append(f'(i64.extend_i32_s (call $a{fi} (local.get $x) (local.get $z)))')
        fi += 1
for c in c64:
    for op in ops32:
        if not ok(op, c): continue
        out.append(f'  (func $a{fi} (param i64) (result i64) (i64.{op} (local.get 0) (i64.const {c})))')
        mix.append(f'(call $a{fi} (local.get $y))')
        fi += 1
body = []
body.append('    (local $h i64)')
for m in mix:
    body.append(f'    (local.set $h (i64.add (i64.mul (local.get $h) (i64.const 1000003)) {m}))')
body.append('    (local.get $h)')
out.append('  (func $all (param $x i32) (param $z i32) (param $y i64) (result i64)\n' + '\n'.join(body) + ')')
# inline variant: many values live at once
inl = ['    (local $h i64) (local $p i32) (local $q i64)']
inl.append('    (local.set $p (i32.add (local.get $x) (local.get $z)))')
inl.append('    (local.set $q (i64.xor (local.get $y) (i64.const 12345)))')
k = 0
for c in c32[:24]:
    for op in ops32:
        if not ok(op, c): continue
        inl.append(f'    (local.set $h (i64.add (i64.rotl (local.get $h) (i64.const 7)) (i64.extend_i32_s (i32.{op} (local.get $p) (i32.const {c})))))')
        inl.append(f'    (local.set $h (i64.xor (local.get $h) (i64.extend_i32_u (i32.{op} (i32.mul (local.get $x) (i32.const 3)) (i32.const {c})))))')
for c in c64[:24]:
    for op in ops32:
        if not ok(op, c): continue
        inl.append(f'    (local.set $h (i64.add (i64.rotl (local.get $h) (i64.const 9)) (i64.{op} (local.get $q) (i64.const {c}))))')
inl.append('    (i64.add (local.get $h) (i64.add (i64.extend_i32_s (local.get $p)) (local.get $q)))')
out.append('  (func $inl (param $x i32) (param $z i32) (param $y i64) (result i64)\n' + '\n'.join(inl) + ')')
# driver
xs32 = [0,1,-1,2,-2,3,7,-7,159,160,161,-160,-2147483648,-2147483647,2147483647,2147483646,12345678,-12345678,1000000007,-1000000007,65535,65536,-65536,0x55555555,-0x55555556]
xs64 = [0,1,-1,2,-2,3,7,-7,160,-160,(1<<63)-1,-(1<<63),-(1<<63)+1,(1<<62),(1<<32),-(1<<32),(1<<32)-1,10**18,-(10**18),123456789123456789,-987654321987654321,0x5555555555555555,-0x5555555555555556]
drv = ['    (local $h i64) (local $i i32) (local $s i64)']
drv.append('    (local.set $s (i64.const 88172645463325252))')
for a in xs32:
    for b in [0, 1, 2147483647, -1]:
        drv.append(f'    (local.set $h (i64.add (i64.mul (local.get $h) (i64.const 31)) (call $all (i32.const {a}) (i32.const {b}) (i64.const {xs64[(a*7+b) % len(xs64)]}))))')
        drv.append(f'    (local.set $h (i64.xor (local.get $h) (call $inl (i32.const {a}) (i32.const {b}) (i64.const {xs64[(a*3+b) % len(xs64)]}))))')
drv.append('''    (loop $L
      (local.set $s (i64.xor (local.get $s) (i64.shl (local.get $s) (i64.const 13))))
      (local.set $s (i64.xor (local.get $s) (i64.shr_u (local.get $s) (i64.const 7))))
      (local.set $s (i64.xor (local.get $s) (i64.shl (local.get $s) (i64.const 17))))
      (local.set $h (i64.add (i64.mul (local.get $h) (i64.const 31))
         (call $all (i32.wrap_i64 (local.get $s)) (i32.wrap_i64 (i64.shr_u (local.get $s) (i64.const 40))) (i64.shr_s (local.get $s) (i64.and (local.get $s) (i64.const 63))))))
      (local.set $h (i64.xor (local.get $h)
         (call $inl (i32.wrap_i64 (i64.shr_u (local.get $s) (i64.const 32))) (i32.wrap_i64 (local.get $s)) (local.get $s))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $L (i32.lt_u (local.get $i) (i32.const 3000))))''')
drv.append('    (local.get $h)')
out.append('  (func (export "check") (result i64)\n' + '\n'.join(drv) + ')')
out.append(')')
open(sys.argv[1], 'w').write('\n'.join(out))
PY
wasm-tools parse "$WORK/d.wat" -o "$WORK/d.wasm" || exit 2
ref=$(wasmtime run -C cache=n --invoke check "$WORK/d.wasm" 2>/dev/null)
[ -n "$ref" ] || { echo "reference run failed"; exit 2; }
fail=0
for mode in "" "NURL_NWASM_RJIT=0" "NURL_NWASM_JIT=0"; do
  got=$(env $mode "$NW" run --invoke check "$WORK/d.wasm" 2>&1)
  if [ "$got" = "$ref" ]; then echo "ok   [${mode:-default}] $got"; else echo "DIFF [${mode:-default}] got=$got ref=$ref"; fail=1; fi
done
[ $fail = 0 ] && echo DIVCONST-CLEAN
exit $fail
