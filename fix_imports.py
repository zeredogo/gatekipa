import os
import re

LIB_DIR = '/Users/mac/Gatekeeper/lib'

def fix_imports(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    lines = content.split('\n')
    new_lines = []
    changed = False

    for line in lines:
        match = re.search(r"import\s+['\"]((?:\.\./)+)(.*\.dart)['\"];", line)
        if match:
            # We have a relative import navigating upwards
            relative_path = match.group(1) + match.group(2)
            
            # The directory of the current file
            current_dir = os.path.dirname(filepath)
            
            # Resolve the absolute path
            abs_path = os.path.normpath(os.path.join(current_dir, relative_path))
            
            # Ensure it's inside lib
            if abs_path.startswith(LIB_DIR):
                package_path = abs_path.replace(LIB_DIR, "package:gatekeeper", 1)
                new_line = line[:match.start()] + f"import '{package_path}';" + line[match.end():]
                new_lines.append(new_line)
                changed = True
            else:
                new_lines.append(line)
        else:
            match_same_dir = re.search(r"import\s+['\"](\./[^\.]+\.dart)['\"];", line)
            if match_same_dir:
               # same dir import
               rel = match_same_dir.group(1)
               cur = os.path.dirname(filepath)
               abs_path = os.path.normpath(os.path.join(cur, rel))
               if abs_path.startswith(LIB_DIR):
                   package_path = abs_path.replace(LIB_DIR, "package:gatekeeper", 1)
                   new_line = line[:match_same_dir.start()] + f"import '{package_path}';" + line[match_same_dir.end():]
                   new_lines.append(new_line)
                   changed = True
               else:
                   new_lines.append(line)
            else:
               # There are also imports like import 'features/auth/foo.dart'; but dart usually prefers relative or package. 
               # Let's handle imports that don't start with package:, dart:, or ./, ../
               match_bare = re.search(r"^import\s+['\"]([^/\.][^:]*\.dart)['\"];", line)
               if match_bare and not line.startswith("import 'package:") and not line.startswith("import 'dart:"):
                   bare_path = match_bare.group(1)
                   cur = os.path.dirname(filepath)
                   abs_path = os.path.normpath(os.path.join(cur, bare_path))
                   if abs_path.startswith(LIB_DIR):
                        package_path = abs_path.replace(LIB_DIR, "package:gatekeeper", 1)
                        new_line = line[:match_bare.start()] + f"import '{package_path}';" + line[match_bare.end():]
                        new_lines.append(new_line)
                        changed = True
                   else:
                        new_lines.append(line)
               else:
                   new_lines.append(line)

    if changed:
        with open(filepath, 'w') as f:
            f.write('\n'.join(new_lines))

for root, dirs, files in os.walk(LIB_DIR):
    for file in files:
        if file.endswith('.dart'):
            fix_imports(os.path.join(root, file))

print("Imports standardized.")
