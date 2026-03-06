import sys
text = open('build_error.txt', 'rb').read().decode('utf-16le', errors='ignore')
for line in text.splitlines():
    if 'failed' in line.lower() or 'error' in line.lower():
        print(line)
