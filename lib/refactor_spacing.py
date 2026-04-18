import os
import re

LIB_DIR = '/Users/mac/Gatekeeper/lib'

space_map = {
    '4': 'AppSpacing.xxs',
    '8': 'AppSpacing.xs',
    '12': 'AppSpacing.sm',
    '16': 'AppSpacing.md',
    '24': 'AppSpacing.lg',
    '32': 'AppSpacing.xl',
    '48': 'AppSpacing.xxl',
    '64': 'AppSpacing.xxxl'
}

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    changed = False

    # Replace SizedBox(height: X)
    for num, token in space_map.items():
        pattern = r"SizedBox\(\s*height\s*:\s*" + num + r"(?:\.0)?\s*\)"
        repl = f"SizedBox(height: {token})"
        new_content, count = re.subn(pattern, repl, content)
        if count > 0:
            content = new_content
            changed = True

        pattern2 = r"SizedBox\(\s*width\s*:\s*" + num + r"(?:\.0)?\s*\)"
        repl2 = f"SizedBox(width: {token})"
        new_content, count = re.subn(pattern2, repl2, content)
        if count > 0:
            content = new_content
            changed = True

    if changed:
        # Add import if missing
        if "app_spacing.dart" not in content:
            import_statement = "import 'package:gatekipa/core/theme/app_spacing.dart';\n"
            # find last import
            match = re.search(r"import\s+['\"].*?['\"];\n", content)
            if match:
               last_import_pos = content.rfind("import '")
               end_pos = content.find(";\n", last_import_pos) + 2
               content = content[:end_pos] + import_statement + content[end_pos:]
            else:
               content = import_statement + content

        with open(filepath, 'w') as f:
            f.write(content)

for root, dirs, files in os.walk(LIB_DIR):
    for file in files:
        if file.endswith('.dart') and file != 'app_spacing.dart':
            fix_file(os.path.join(root, file))

print("Spacing standardized.")
