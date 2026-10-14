import unicodedata, sys
def ranges(pred):
    out=[];start=None
    for cp in range(0x110000):
        ok=pred(cp)
        if ok and start is None: start=cp
        if not ok and start is not None: out.append((start,cp-1)); start=None
    if start is not None: out.append((start,0x10FFFF))
    return out
L=ranges(lambda c: unicodedata.category(chr(c)).startswith('L'))
N=ranges(lambda c: unicodedata.category(chr(c)).startswith('N'))
S=ranges(lambda c: chr(c).isspace())
def body(name,rs):
    lines=[f"@ __uc_{name}_make → ( Arc ( Vec i ) ) {{","    : ( Vec i ) v ( vec_with_cap [i] "+str(2*len(rs))+" )"]
    flat=[x for r in rs for x in r]
    for k in range(0,len(flat),16):
        lines.append("    "+" ".join(f"( vec_push [i] v {x} )" for x in flat[k:k+16]))
    lines.append(f"    ^ ( arc_new [( Vec i )] v )")
    lines.append("}")
    lines.append("")
    lines.append(f": ( Arc ( Vec i ) ) g_uc_{name} ( __uc_{name}_make )")
    lines.append("")
    return "\n".join(lines)
print(f"""// stdlib/std/unicat.nu — Unicode general categories a tokenizer's
// pre-tokenizer asks about: is a codepoint a letter (\\p{{L}}), a number
// (\\p{{N}}), white space (\\s)? Generated from Unicode {unicodedata.unidata_version}
// (Python's unicodedata) by tools/gen_unicat.py: sorted [first, last]
// ranges, built once at start and searched by halves.
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/slice.nu`

// Is `c` inside one of the ranges `rs` holds (first, last, first, …)?
@ __uc_in ( Vec i ) rs i c → b {{
    : ( Slice i ) r ( slice_from_vec [i] rs )
    : ~ i lo 0
    : ~ i hi / ( slice_len [i] r ) 2
    ~ < lo hi {{
        : i mid / + lo hi 2
        : i k * mid 2
        ? < c ( slice_at [i] r k ) {{ = hi mid }} {{
            ? > c ( slice_at [i] r + k 1 ) {{ = lo + mid 1 }} {{ ^ T }}
        }}
    }}
    ^ F
}}

{body('l',L)}
{body('n',N)}
{body('s',S)}
// A letter: general category L (Lu Ll Lt Lm Lo).
@ uc_is_letter i c → b {{
    ? < c 128 {{ ^ | & >= c 65 <= c 90 & >= c 97 <= c 122 }} {{}}
    ^ ( __uc_in ( arc_get [( Vec i )] g_uc_l ) c )
}}

// A number: general category N (Nd Nl No).
@ uc_is_number i c → b {{
    ? < c 128 {{ ^ & >= c 48 <= c 57 }} {{}}
    ^ ( __uc_in ( arc_get [( Vec i )] g_uc_n ) c )
}}

// White space, as a regex's \\s means it.
@ uc_is_space i c → b {{
    ? < c 128 {{ ^ | == c 32 & >= c 9 <= c 13 }} {{}}
    ^ ( __uc_in ( arc_get [( Vec i )] g_uc_s ) c )
}}
""")
print(len(L),len(N),len(S),file=sys.stderr)
