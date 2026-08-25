#!/usr/bin/env python3
# Print "name<TAB>flag" (fuzz_diff.sh helper) for each exported function of a wasm module:
# flags: N = takes params (skip), I = all results i32/i64 (exact compare),
#        F = has float/ref results (class-compare only)
import re, subprocess, sys

wat = subprocess.run(['wasm-tools', 'print', sys.argv[1]], capture_output=True, text=True).stdout
types = {}
for line in wat.splitlines():
    m = re.match(r'\s*\(type \(;(\d+);\) \(func(.*)\)\)\s*$', line)
    if not m:
        continue
    ti = int(m.group(1)); body = m.group(2)
    np = sum(len(g.split()) for g in re.findall(r'\(param([^)]*)\)', body))
    res = [t for g in re.findall(r'\(result([^)]*)\)', body) for t in g.split()]
    types[ti] = (np, res)
functype = {}
for m in re.finditer(r'\(func \(;(\d+);\) \(type (\d+)\)', wat):
    functype[int(m.group(1))] = int(m.group(2))
for m in re.finditer(r'\(export "([^"]*)" \(func (\d+)\)', wat):
    name, fi = m.group(1), int(m.group(2))
    np, res = types.get(functype.get(fi, -1), (0, []))
    if np:
        flag = 'N'
    elif all(r in ('i32', 'i64') for r in res):
        flag = 'I'
    else:
        flag = 'F'
    print(f'{name}\t{flag}')
