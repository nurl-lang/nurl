// benchmark-contract: json-parse;input=bench/data.json;parses=20
//
// json_parse — parse bench/data.json 20 times with a small
// recursive-descent parser, building an owned DOM tree each pass and
// freeing it, and print how many parses succeeded.
//
// C has no JSON in its standard library, so — exactly like the Rust
// peer — the parser is embedded here rather than pulled in as a
// dependency: every language uses what ships in its box plus, where the
// box is empty, a hand-written parser in the benchmark file itself.
// Python (`json`), Node (`JSON.parse`) and NURL (`stdlib/ext/json.nu`)
// all use their own.
//
// The row's blurb is "allocator pressure, string handling, recursive
// descent", and every peer builds a document tree: Python and Node
// cannot avoid it, NURL and Rust build one deliberately. An earlier
// version of this file only *validated* — no tree, no strings, no
// allocation — which made the C cell a measurement of different work.
// This parser mirrors the Rust peer structure for structure: strings
// are copied into owned buffers, numbers keep a borrowed slice of the
// source, arrays and objects are growable vectors, and the whole tree
// is freed after each parse.
//
// Contract: the process prints exactly one line — the number of parses
// that succeeded. This is the one row in the suite whose cross-language
// gate is "every parser accepted the document" rather than a structural
// checksum of what came out.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ } JTag;

typedef struct JVal JVal;
typedef struct JKv JKv;

struct JVal {
  JTag tag;
  union {
    int boolean;
    struct { const char* p; size_t len; } num;  // borrowed from src
    char* str;                                  // owned copy
    struct { JVal* items; size_t len, cap; } arr;
    struct { JKv* items; size_t len, cap; } obj;
  } u;
};

struct JKv {
  char* key;  // owned copy
  JVal val;
};

static void jval_free(JVal* v) {
  switch (v->tag) {
    case J_STR:
      free(v->u.str);
      break;
    case J_ARR:
      for (size_t i = 0; i < v->u.arr.len; ++i) jval_free(&v->u.arr.items[i]);
      free(v->u.arr.items);
      break;
    case J_OBJ:
      for (size_t i = 0; i < v->u.obj.len; ++i) {
        free(v->u.obj.items[i].key);
        jval_free(&v->u.obj.items[i].val);
      }
      free(v->u.obj.items);
      break;
    default:
      break;
  }
}

typedef struct {
  const unsigned char* s;
  size_t len;
  size_t i;
} P;

static int parse_value(P* p, JVal* out);

static void skip_ws(P* p) {
  while (p->i < p->len) {
    unsigned char c = p->s[p->i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      ++p->i;
    } else {
      break;
    }
  }
}

static int match_kw(P* p, const char* kw, size_t n) {
  if (p->len - p->i < n) {
    return 0;
  }
  if (memcmp(p->s + p->i, kw, n) != 0) {
    return 0;
  }
  p->i += n;
  return 1;
}

// The benchmark input carries no escapes, matching the Rust peer, which
// bails out on a backslash rather than decoding it. The body bytes are
// copied into an owned NUL-terminated buffer, like Rust's String.
static char* parse_string_owned(P* p) {
  ++p->i;
  size_t start = p->i;
  while (p->i < p->len) {
    unsigned char c = p->s[p->i];
    if (c == '"') {
      size_t n = p->i - start;
      char* out = (char*)malloc(n + 1);
      if (!out) return NULL;
      memcpy(out, p->s + start, n);
      out[n] = '\0';
      ++p->i;
      return out;
    }
    if (c == '\\') {
      return NULL;  // skip escape handling — bench input has none
    }
    ++p->i;
  }
  return NULL;
}

static int parse_number(P* p, JVal* out) {
  size_t start = p->i;
  if (p->i < p->len && p->s[p->i] == '-') ++p->i;
  while (p->i < p->len) {
    unsigned char c = p->s[p->i];
    if ((c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' ||
        c == '+' || c == '-') {
      ++p->i;
    } else {
      break;
    }
  }
  if (p->i == start) return 0;
  out->tag = J_NUM;
  out->u.num.p = (const char*)p->s + start;
  out->u.num.len = p->i - start;
  return 1;
}

static int parse_array(P* p, JVal* out) {
  ++p->i;
  out->tag = J_ARR;
  out->u.arr.items = NULL;
  out->u.arr.len = 0;
  out->u.arr.cap = 0;
  skip_ws(p);
  if (p->i < p->len && p->s[p->i] == ']') {
    ++p->i;
    return 1;
  }
  for (;;) {
    if (out->u.arr.len == out->u.arr.cap) {
      size_t nc = out->u.arr.cap ? out->u.arr.cap * 2 : 4;
      JVal* ni = (JVal*)realloc(out->u.arr.items, nc * sizeof(JVal));
      if (!ni) { jval_free(out); return 0; }
      out->u.arr.items = ni;
      out->u.arr.cap = nc;
    }
    if (!parse_value(p, &out->u.arr.items[out->u.arr.len])) {
      jval_free(out);
      return 0;
    }
    out->u.arr.len++;
    skip_ws(p);
    if (p->i >= p->len) { jval_free(out); return 0; }
    if (p->s[p->i] == ',') {
      ++p->i;
    } else if (p->s[p->i] == ']') {
      ++p->i;
      return 1;
    } else {
      jval_free(out);
      return 0;
    }
  }
}

static int parse_object(P* p, JVal* out) {
  ++p->i;
  out->tag = J_OBJ;
  out->u.obj.items = NULL;
  out->u.obj.len = 0;
  out->u.obj.cap = 0;
  skip_ws(p);
  if (p->i < p->len && p->s[p->i] == '}') {
    ++p->i;
    return 1;
  }
  for (;;) {
    skip_ws(p);
    if (p->i >= p->len || p->s[p->i] != '"') { jval_free(out); return 0; }
    char* key = parse_string_owned(p);
    if (!key) { jval_free(out); return 0; }
    skip_ws(p);
    if (p->i >= p->len || p->s[p->i] != ':') { free(key); jval_free(out); return 0; }
    ++p->i;
    if (out->u.obj.len == out->u.obj.cap) {
      size_t nc = out->u.obj.cap ? out->u.obj.cap * 2 : 4;
      JKv* ni = (JKv*)realloc(out->u.obj.items, nc * sizeof(JKv));
      if (!ni) { free(key); jval_free(out); return 0; }
      out->u.obj.items = ni;
      out->u.obj.cap = nc;
    }
    JKv* kv = &out->u.obj.items[out->u.obj.len];
    kv->key = key;
    if (!parse_value(p, &kv->val)) {
      free(key);
      jval_free(out);
      return 0;
    }
    out->u.obj.len++;
    skip_ws(p);
    if (p->i >= p->len) { jval_free(out); return 0; }
    if (p->s[p->i] == ',') {
      ++p->i;
    } else if (p->s[p->i] == '}') {
      ++p->i;
      return 1;
    } else {
      jval_free(out);
      return 0;
    }
  }
}

static int parse_value(P* p, JVal* out) {
  skip_ws(p);
  if (p->i >= p->len) return 0;
  unsigned char c = p->s[p->i];
  switch (c) {
    case 'n':
      if (!match_kw(p, "null", 4)) return 0;
      out->tag = J_NULL;
      return 1;
    case 't':
      if (!match_kw(p, "true", 4)) return 0;
      out->tag = J_BOOL;
      out->u.boolean = 1;
      return 1;
    case 'f':
      if (!match_kw(p, "false", 5)) return 0;
      out->tag = J_BOOL;
      out->u.boolean = 0;
      return 1;
    case '"': {
      char* s = parse_string_owned(p);
      if (!s) return 0;
      out->tag = J_STR;
      out->u.str = s;
      return 1;
    }
    case '[':
      return parse_array(p, out);
    case '{':
      return parse_object(p, out);
    default:
      return parse_number(p, out);
  }
}

int main(void) {
  FILE* f = fopen("bench/data.json", "rb");
  if (!f) {
    fprintf(stderr, "json_parse: cannot open bench/data.json\n");
    return 1;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (size <= 0) {
    fclose(f);
    return 1;
  }
  unsigned char* src = (unsigned char*)malloc((size_t)size);
  if (!src || fread(src, 1, (size_t)size, f) != (size_t)size) {
    fclose(f);
    return 1;
  }
  fclose(f);

  int ok = 0;
  for (int pass = 0; pass < 20; ++pass) {
    P p = {src, (size_t)size, 0};
    JVal root;
    if (parse_value(&p, &root)) {
      skip_ws(&p);
      if (p.i == p.len) {
        ++ok;
      }
      jval_free(&root);
    }
  }
  free(src);
  printf("%d\n", ok);
  return 0;
}
