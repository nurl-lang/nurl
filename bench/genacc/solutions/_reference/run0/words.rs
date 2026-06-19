// words — count words (maximal runs of ASCII letters) in an embedded string.
fn is_letter(c: u8) -> bool {
    (97..=122).contains(&c) || (65..=90).contains(&c)
}

fn main() {
    let text = "the quick123brown fox, jumps-over the lazy_dog!";
    let mut count = 0;
    let mut inword = false;
    for &c in text.as_bytes() {
        if is_letter(c) {
            if !inword {
                count += 1;
                inword = true;
            }
        } else {
            inword = false;
        }
    }
    println!("{}", count);
}
