import subprocess
import os

try:
    print("Running flutter build apk...")
    result = subprocess.run(['flutter.bat', 'build', 'apk'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', shell=True)
    with open('clean_error.txt', 'w', encoding='utf-8') as f:
        f.write(result.stdout)
    print("Finished flutter build.")
except Exception as e:
    print(f"Failed to run flutter build: {e}")
