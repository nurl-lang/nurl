// benchmark-contract: json-parse;input=bench/data.json;parses=20
//
// json_parse — parse bench/data.json 20 times with a small
// recursive-descent parser and print how many parses succeeded.
//
// C has no JSON in its standard library, so — exactly like the Rust
// peer — the parser is embedded here rather than pulled in as a
// dependency: every language uses what ships in its box plus, where the
// box is empty, a hand-written parser in the benchmark file itself.
// Python (`json`), Node (`JSON.parse`) and NURL (`stdlib/ext/json.nu`)
// all use their own.
//
// Contract: the process prints exactly one line — the number of parses
// that succeeded. This is the one row in the suite whose cross-language
// gate is "every parser accepted the document" rather than a structural
// checksum of what came out.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  const unsigned char* s;
  size_t len;
  size_t i;
} P;

static int parse_value(P* p);

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
// bails out on a backslash rather than decoding it.
static int parse_string(P* p) {
  ++p->i;
  while (p->i < p->len) {
    unsigned char c = p->s[p->i];
    if (c == '"') {
      ++p->i;
      return 1;
    }
    if (c == '\\') {
      return 0;
    }
    ++p->i;
  }
  return 0;
}

static int parse_number(P* p) {
  size_t start = p->i;
  if (p->s[p->i] == '-') {
    ++p->i;
  }
  while (p->i < p->len) {
    unsigned char c = p->s[p->i];
    int numeric = (c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' ||
                  c == '+' || c == '-';
    if (!numeric) {
      break;
    }
    ++p->i;
  }
  return p->i > start;
}

static int parse_array(P* p) {
  ++p->i;
  skip_ws(p);
  if (p->i < p->len && p->s[p->i] == ']') {
    ++p->i;
    return 1;
  }
  for (;;) {
    if (!parse_value(p)) {
      return 0;
    }
    skip_ws(p);
    if (p->i >= p->len) {
      return 0;
    }
    if (p->s[p->i] == ',') {
      ++p->i;
      continue;
    }
    if (p->s[p->i] == ']') {
      ++p->i;
      return 1;
    }
    return 0;
  }
}

static int parse_object(P* p) {
  ++p->i;
  skip_ws(p);
  if (p->i < p->len && p->s[p->i] == '}') {
    ++p->i;
    return 1;
  }
  for (;;) {
    skip_ws(p);
    if (p->i >= p->len || p->s[p->i] != '"') {
      return 0;
    }
    if (!parse_string(p)) {
      return 0;
    }
    skip_ws(p);
    if (p->i >= p->len || p->s[p->i] != ':') {
      return 0;
    }
    ++p->i;
    if (!parse_value(p)) {
      return 0;
    }
    skip_ws(p);
    if (p->i >= p->len) {
      return 0;
    }
    if (p->s[p->i] == ',') {
      ++p->i;
      continue;
    }
    if (p->s[p->i] == '}') {
      ++p->i;
      return 1;
    }
    return 0;
  }
}

static int parse_value(P* p) {
  skip_ws(p);
  if (p->i >= p->len) {
    return 0;
  }
  switch (p->s[p->i]) {
    case 'n': return match_kw(p, "null", 4);
    case 't': return match_kw(p, "true", 4);
    case 'f': return match_kw(p, "false", 5);
    case '"': return parse_string(p);
    case '[': return parse_array(p);
    case '{': return parse_object(p);
    default:  return parse_number(p);
  }
}

int main(void) {
  // Resolved against the working directory, like the NURL and Rust
  // peers: the runner always invokes the benchmarks from the repo root.
  FILE* f = fopen("bench/data.json", "rb");
  if (f == NULL) {
    fprintf(stderr, "json_parse: cannot open bench/data.json\n");
    return 1;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  unsigned char* src = (unsigned char*)malloc((size_t)size);
  if (src == NULL || fread(src, 1, (size_t)size, f) != (size_t)size) {
    fclose(f);
    return 1;
  }
  fclose(f);

  int ok = 0;
  for (int r = 0; r < 20; ++r) {
    P p = {src, (size_t)size, 0};
    if (parse_value(&p)) {
      ++ok;
    }
  }

  printf("%d\n", ok);
  free(src);
  return 0;
}
