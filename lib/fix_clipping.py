import os
import re

LIB_DIR = '/Users/mac/Gatekeeper/lib'

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Only replace TextStyle( that doesn't already have fontFamily or height
    # We will match "TextStyle(" and add "height: 1.2, fontFamily: 'Manrope', "
    
    changed = False
    
    # regex to match TextStyle( followed by anything that isn't already font family
    def replacer(match):
        return "TextStyle(height: 1.2, fontFamily: 'Manrope', "

    new_content, count = re.subn(r"TextStyle\(\s*(?!height|fontFamily)", replacer, content)
    
    if count > 0:
        with open(filepath, 'w') as f:
            f.write(new_content)
        return True
    return False

files_changed = 0
for root, dirs, files in os.walk(LIB_DIR):
    for file in files:
        if file.endswith('.dart'):
             if 'app_theme.dart' in file:
                 continue
             if fix_file(os.path.join(root, file)):
                 files_changed += 1

print(f"Fixed {files_changed} files.")
