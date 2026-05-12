import csv
import random
import datetime
import string
import sys

# Fixed seed: every regeneration of test_data.csv must produce the same
# bytes. Keeps benchmarks comparable across machines and across days.
SEED = 0xC0FFEE

def generate_random_string(length, include_numbers=False):
    chars = string.ascii_letters + " "
    if include_numbers:
        chars += string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def generate_data(filename, num_rows):
    random.seed(SEED)
    start_date = datetime.date(2022, 1, 1)
    end_date = datetime.date(2026, 5, 1)
    time_between_dates = end_date - start_date
    days_between_dates = time_between_dates.days

    headers = ["id", "val_int", "val_float1", "val_float2", "text_simple", "text_mixed", "text_words", "date"]
    
    words = ["apple", "banana", "cherry", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"]

    with open(filename, mode='w', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        writer.writerow(headers)
        
        for i in range(1, num_rows + 1):
            random_number_of_days = random.randrange(days_between_dates)
            random_date = start_date + datetime.timedelta(days=random_number_of_days)
            
            row = [
                i,
                random.randint(100, 1000000),
                round(random.uniform(0, 100), 4),
                round(random.uniform(-1000, 1000), 2),
                generate_random_string(20),
                generate_random_string(25, include_numbers=True),
                " ".join(random.sample(words, 3)),
                random_date.strftime("%Y-%m-%d")
            ]
            writer.writerow(row)
            
            if i % 100000 == 0:
                print(f"Generated {i} rows...")

if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000000
    out = sys.argv[2] if len(sys.argv) > 2 else "test_data.csv"
    generate_data(out, n)
    print(f"Done generating {out} ({n} rows, seed=0x{SEED:X})")
