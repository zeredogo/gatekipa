import os
import re

LIB_DIR = '/Users/mac/Gatekeeper/lib'

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    changed = False

    # Regex to find GoogleFonts.manrope(...) or GoogleFonts.inter(...)
    # We want to replace it with Theme.of(context).textTheme.bodyMedium?.copyWith(...)
    # Wait, simple mapping:
    # manrope -> Theme.of(context).textTheme.titleMedium?.copyWith(...)
    # inter -> Theme.of(context).textTheme.bodyMedium?.copyWith(...)
    
    # We will do a generic replacement:
    
    pattern_manrope = r"GoogleFonts\.manrope\s*\(([^)]*)\)"
    def repl_manrope(match):
        args = match.group(1).strip()
        if not args:
             return "Theme.of(context).textTheme.titleMedium"
        return f"Theme.of(context).textTheme.titleMedium?.copyWith({args})"

    new_content, count = re.subn(pattern_manrope, repl_manrope, content)
    if count > 0:
        content = new_content
        changed = True

    pattern_inter = r"GoogleFonts\.inter\s*\(([^)]*)\)"
    def repl_inter(match):
        args = match.group(1).strip()
        if not args:
             return "Theme.of(context).textTheme.bodyMedium"
        return f"Theme.of(context).textTheme.bodyMedium?.copyWith({args})"
        
    new_content, count = re.subn(pattern_inter, repl_inter, content)
    if count > 0:
        content = new_content
        changed = True

    if changed:
        with open(filepath, 'w') as f:
            f.write(content)

for root, dirs, files in os.walk(LIB_DIR):
    for file in files:
        if file.endswith('.dart'):
             if 'app_theme.dart' in file or 'gk_button.dart' in file:
                 continue
             fix_file(os.path.join(root, file))

print("Typography refactored.")
