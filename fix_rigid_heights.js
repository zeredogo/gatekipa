const fs = require('fs');
const path = require('path');

function fixRigidButtonHeights(dir) {
    let fixedCount = 0;

    function scanDir(currentPath) {
        const files = fs.readdirSync(currentPath);
        for (const file of files) {
            const fullPath = path.join(currentPath, file);
            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) {
                scanDir(fullPath);
            } else if (fullPath.endsWith('.dart')) {
                let content = fs.readFileSync(fullPath, 'utf8');
                
                // Regex to find:
                // SizedBox(
                //   width: double.infinity,
                //   height: 48,
                //   child: FilledButton...
                
                // We will look for 'height: XX,' and replace it if the child is a Button.
                // Because parsing Dart with regex is tricky, we'll do a line-by-line state machine.
                
                let lines = content.split('\n');
                let modified = false;
                
                for (let i = 0; i < lines.length; i++) {
                    const match = lines[i].match(/^(\s*)height:\s*(\d+(?:\.\d+)?),/);
                    if (match) {
                        const indent = match[1];
                        const heightVal = match[2];
                        
                        // Check if it's inside a SizedBox or Container
                        let isBox = false;
                        for (let j = i - 1; j >= Math.max(0, i - 5); j--) {
                            if (lines[j].includes('SizedBox(') || lines[j].includes('Container(')) {
                                isBox = true;
                                break;
                            }
                        }
                        
                        // Check if the child is a Button
                        let hasButton = false;
                        for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                            if (lines[i+j].match(/(FilledButton|ElevatedButton|OutlinedButton|TextButton)/)) {
                                hasButton = true;
                                break;
                            }
                        }
                        
                        if (isBox && hasButton) {
                            // Replace height with constraints
                            lines[i] = `${indent}constraints: const BoxConstraints(minHeight: ${heightVal}), // FIX: Flexible height`;
                            modified = true;
                            fixedCount++;
                            
                            // Also, if the wrapper was a SizedBox, change it to Container
                            for (let j = i - 1; j >= Math.max(0, i - 5); j--) {
                                if (lines[j].includes('SizedBox(')) {
                                    // Change SizedBox to Container because SizedBox doesn't take constraints
                                    lines[j] = lines[j].replace(/SizedBox\s*\(/, 'Container(');
                                    // Remove 'const ' before SizedBox if it exists, since Container with BoxConstraints might not be const if child isn't const
                                    lines[j] = lines[j].replace(/const\s+Container\(/, 'Container(');
                                    break;
                                }
                            }
                        }
                    }
                }
                
                if (modified) {
                    fs.writeFileSync(fullPath, lines.join('\n'));
                }
            }
        }
    }

    scanDir(dir);
    return fixedCount;
}

const count = fixRigidButtonHeights('/Users/mac/Gatekipa/lib');
console.log(`Successfully converted ${count} rigid height constraints to flexible minimum sizes app-wide.`);
