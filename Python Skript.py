import re
from collections import Counter

def analyze_uvm_log(log_file_path):
    # תבניות לחיפוש הודעות UVM ספציפיות מהקוד שלך
    patterns = {
        'match': r'UVM_INFO.*SB \[SB\] MATCH! Data: ([0-9a-fA-F]+)',
        'mismatch': r'UVM_ERROR.*SB \[SB\] MISMATCH! Exp: ([0-9a-fA-F]+), Got: ([0-9a-fA-F]+)',
        'timeout': r'UVM_ERROR.*DRV_TIMEOUT',
        'coverage': r'UVM_INFO.*COV \[COV\] Final Coverage Score: ([\d.]+)'
    }

    results = {
        'matches': 0,
        'mismatches': 0,
        'timeouts': 0,
        'final_coverage': 0.0,
        'captured_data': []
    }

    try:
        with open(log_file_path, 'r') as file:
            for line in file:
                # חיפוש Match
                match_found = re.search(patterns['match'], line)
                if match_found:
                    results['matches'] += 1
                    results['captured_data'].append(match_found.group(1))

                # חיפוש Mismatch
                if re.search(patterns['mismatch'], line):
                    results['mismatches'] += 1

                # חיפוש Timeout בדרייבר
                if re.search(patterns['timeout'], line):
                    results['timeouts'] += 1

                # חילוץ אחוז כיסוי
                cov_found = re.search(patterns['coverage'], line)
                if cov_found:
                    results['final_coverage'] = float(cov_found.group(1))

        print_summary(results)

    except FileNotFoundError:
        print(f"Error: The file '{log_file_path}' was not found.")

def print_summary(res):
    print("-" * 30)
    print("   UVM SIMULATION SUMMARY")
    print("-" * 30)
    print(f"✅ Total Matches:    {res['matches']}")
    print(f"❌ Total Mismatches: {res['mismatches']}")
    print(f"⚠️  Driver Timeouts:  {res['timeouts']}")
    print(f"📊 Final Coverage:   {res['final_coverage']}%")
    print("-" * 30)
    
    if res['mismatches'] > 0 or res['timeouts'] > 0:
        print("STATUS: FAILED 🔴")
    else:
        print("STATUS: PASSED 🟢")

# הרצה לדוגמה (בהנחה שיש קובץ שנקרא simulation.log)
if __name__ == "__main__":
    analyze_uvm_log("simulation.log")
