import csv
import os
import time
from datetime import datetime

def sort_csv(input_file, output_file):
    # Remove existing output file if it exists
    if os.path.exists(output_file):
        os.remove(output_file)
        print(f"Removed existing {output_file}")

    start_time = time.time()
    print(f"Starting sort process at {datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')}")

    try:
        # Read data
        with open(input_file, mode='r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            data = list(reader)
        
        read_done_time = time.time()
        print(f"Read {len(data)} rows in {read_done_time - start_time:.4f} seconds.")

        # Sort data using all columns as keys (descending)
        data.sort(key=lambda x: (
            x['date'], 
            x['text_words'], 
            x['text_mixed'], 
            x['text_simple'], 
            x['val_float2'], 
            x['val_float1'], 
            x['val_int'], 
            x['id']
        ), reverse=True)
        
        sort_done_time = time.time()
        print(f"Sort completed in {sort_done_time - read_done_time:.4f} seconds.")

        # Write data
        fieldnames = data[0].keys() if data else []
        with open(output_file, mode='w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(data)
        
        write_done_time = time.time()
        print(f"Write completed in {write_done_time - sort_done_time:.4f} seconds.")

        end_time = time.time()
        duration = end_time - start_time

        print(f"\nTotal time elapsed: {duration:.4f} seconds")
        print(f"Finished at {datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')}")

    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    sort_csv("test_data.csv", "python_sorted_data.csv")
