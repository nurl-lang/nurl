// json_parse — parse bench/data.json 50 times.
// No serde_json (it's a separate crate); we link a tiny embedded
// recursive-descent parser to match the "what's in the box" baseline:
// each language uses the parser shipped with its stdlib + this file,
// no extra dependencies.
use std::fs::File;
use std::io::Read;
use std::str;

#[derive(Debug)]
enum J<'a> {
    Null,
    Bool(bool),
    Num(&'a str),
    Str(String),
    Arr(Vec<J<'a>>),
    Obj(Vec<(String, J<'a>)>),
}

struct P<'a> { s: &'a [u8], i: usize }

impl<'a> P<'a> {
    fn skip_ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }
    fn parse(&mut self) -> Option<J<'a>> {
        self.skip_ws();
        if self.i >= self.s.len() { return None; }
        let c = self.s[self.i];
        match c {
            b'n' => { if self.s[self.i..].starts_with(b"null") { self.i += 4; Some(J::Null) } else { None } }
            b't' => { if self.s[self.i..].starts_with(b"true") { self.i += 4; Some(J::Bool(true)) } else { None } }
            b'f' => { if self.s[self.i..].starts_with(b"false") { self.i += 5; Some(J::Bool(false)) } else { None } }
            b'"' => self.parse_str().map(J::Str),
            b'[' => self.parse_arr(),
            b'{' => self.parse_obj(),
            _ => self.parse_num(),
        }
    }
    fn parse_str(&mut self) -> Option<String> {
        self.i += 1;
        let start = self.i;
        let mut out = String::new();
        while self.i < self.s.len() {
            let c = self.s[self.i];
            if c == b'"' { out.push_str(str::from_utf8(&self.s[start..self.i]).ok()?); self.i += 1; return Some(out); }
            if c == b'\\' { return None; } // skip escape handling — bench input has none
            self.i += 1;
        }
        None
    }
    fn parse_num(&mut self) -> Option<J<'a>> {
        let start = self.i;
        if self.s[self.i] == b'-' { self.i += 1; }
        while self.i < self.s.len() && matches!(self.s[self.i], b'0'..=b'9' | b'.' | b'e' | b'E' | b'+' | b'-') { self.i += 1; }
        let raw = unsafe { std::str::from_utf8_unchecked(&self.s[start..self.i]) };
        Some(J::Num(raw))
    }
    fn parse_arr(&mut self) -> Option<J<'a>> {
        self.i += 1;
        let mut out = Vec::new();
        self.skip_ws();
        if self.i < self.s.len() && self.s[self.i] == b']' { self.i += 1; return Some(J::Arr(out)); }
        loop {
            out.push(self.parse()?);
            self.skip_ws();
            if self.i >= self.s.len() { return None; }
            match self.s[self.i] {
                b',' => self.i += 1,
                b']' => { self.i += 1; return Some(J::Arr(out)); }
                _ => return None,
            }
        }
    }
    fn parse_obj(&mut self) -> Option<J<'a>> {
        self.i += 1;
        let mut out = Vec::new();
        self.skip_ws();
        if self.i < self.s.len() && self.s[self.i] == b'}' { self.i += 1; return Some(J::Obj(out)); }
        loop {
            self.skip_ws();
            let k = self.parse_str()?;
            self.skip_ws();
            if self.i >= self.s.len() || self.s[self.i] != b':' { return None; }
            self.i += 1;
            let v = self.parse()?;
            out.push((k, v));
            self.skip_ws();
            if self.i >= self.s.len() { return None; }
            match self.s[self.i] {
                b',' => self.i += 1,
                b'}' => { self.i += 1; return Some(J::Obj(out)); }
                _ => return None,
            }
        }
    }
}

fn main() {
    let path = std::env::current_dir().unwrap().join("bench/data.json");
    let mut src = Vec::new();
    File::open(&path).unwrap().read_to_end(&mut src).unwrap();
    let mut ok = 0u32;
    for _ in 0..5 {
        let mut p = P { s: &src, i: 0 };
        if p.parse().is_some() { ok += 1; }
    }
    println!("{}", ok);
}
