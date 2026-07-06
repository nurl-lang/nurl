# template — an HTML template engine for NURL

Jinja-flavoured templates rendered against a stdlib `Json` context.
HTML-escaped by default, lenient on missing data, strict on malformed
tags. The engine is pure text → text with no fs or http dependency;
a directory loader and a small CLI ship alongside it.

```html
<ul>
{% for item in items %}
  <li class="{% if loop.first %}first{% end %}">
    {{ loop.index }}: {{ item.title | upper }}
    {% if item.url %}<a href="{{ item.url }}">link</a>{% end %}
  </li>
{% end %}
</ul>
{% include 'footer' %}
```

## Rendering

```nurl
$ `deps/template/src/template.nu`

: Json ctx ...                            // e.g. ( json_parse src ) or built up
?? ( tpl_render `Hi {{ name }}!` ctx ) {
    T html → { ... ( string_free html ) }
    F err  → { ... ( string_free err ) }   // "template error at line L, col C: …"
}
```

| Call | |
| --- | --- |
| `( tpl_render src ctx )` → `!String String` | one-shot render |
| `( tset_new )` → `*TplSet` | named-template set (include targets) |
| `( tset_add t name src )` | register / replace (copies both) |
| `( tset_has t name )` → `b` | |
| `( tset_render t name ctx )` → `!String String` | render a set member |
| `( tpl_render_with t src ctx )` → `!String String` | one-shot, includes resolve in `t` |
| `( tset_free t )` | |
| `( tset_load_dir t dir ext )` → `i` | `src/loader.nu`: load `dir/*<ext>`, named by basename; -1 when the glob fails |

The context is any `Json` value; top-level lookups expect a `JObj`. The
result and error payloads are owned Strings — free both.

## Template syntax

| Form | |
| --- | --- |
| `{{ expr }}` | output, HTML-escaped (`& < > " '`) |
| `{{ expr \| raw }}` | unescaped output |
| `{{ expr \| upper }}` / `\| lower` | case-fold strings |
| `{{ expr \| length }}` | string byte length / array length |
| `{{ expr \| json }}` | stringify an array/object (escaped; add `\| raw` for raw JSON) |
| `{% if expr %} … {% elif expr %} … {% else %} … {% end %}` | `endif` also accepted |
| `{% for name in path %} … {% end %}` | iterate a JSON array; `endfor` also accepted |
| `{% include 'name' %}` | render a set member in the current context + scope |
| `{# … #}` | comment |

Expressions are a dotted path (`user.name`, `rows.0.id` — numeric
segments index arrays), a `'string'` / `"string"` literal, a number, or
`true`/`false`, optionally combined as `a == b` / `a != b` or prefixed
with `not`. Inside a `{% for %}` body the innermost loop exposes
`loop.index` (0-based), `loop.first`, `loop.last`, `loop.length`; the
loop variable shadows context keys, inner loops shadow outer ones.

**Truthiness:** missing keys and `null` are falsy, as are `false`, `0`,
`""`, and `[]`; objects are truthy. Missing keys *render* as empty, so
`{{ maybe }}` is safe without a guard — but a typo'd tag, filter, or
operator is a hard error, not silence.

**Equality** compares like kinds only: numbers numerically, strings
bytewise, booleans as booleans; a string never equals a number.

## Errors

Failures return an owned String like
`template error at line 3, col 12: '{% if %}' without matching '{% end %}'`.
Include cycles are cut at depth 16. Known v0.1 limits: `}}` / `%}`
inside a string literal ends the tag early; error positions inside an
included template are reported against the including source.

## CLI

```
template -f page.html -c ctx.json -p views/
echo '{{ msg | upper }}' | template -c ctx.json
```

`-f` template file (default stdin), `-c` JSON context file (default
`{}`), `-p` a partials directory (`*.html`, named by basename) for
`{% include %}`.

## Memory model

`tpl_render`'s Ok/Err payloads are owned Strings — free them. The
context `Json` stays caller-owned (the engine only borrows into it).
`tset_add` copies its arguments; `tset_free` releases the set. The
engine allocates one renderer per call and frees it before returning —
the test suite runs clean under ASan/LSan.

## Tests

`nurlpkg test` (or `./nurl.sh tests/<t>.nu` from the package dir) runs
three self-asserting suites: `basic.nu` (variables, escaping, filters,
literals, error paths), `control.nu` (if/elif/else, for, `loop.*`,
nesting, conditions), `includes.nu` (sets, include, cycles, the
directory loader).
