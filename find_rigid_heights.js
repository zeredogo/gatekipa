const fs = require('fs');
const path = require('path');

function findRigidButtonHeights(dir) {
    let count = 0;
    let filesWithIssues = [];

    function scanDir(currentPath) {
        const files = fs.readdirSync(currentPath);
        for (const file of files) {
            const fullPath = path.join(currentPath, file);
            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) {
                scanDir(fullPath);
            } else if (fullPath.endsWith('.dart')) {
                const content = fs.readFileSync(fullPath, 'utf8');
                const lines = content.split('\n');
                
                for (let i = 0; i < lines.length; i++) {
                    // Look for height: 40, height: 48, height: 50, height: 56, etc.
                    if (lines[i].match(/height:\s*\d+/)) {
                        // Look ahead up to 4 lines for a button
                        let hasButton = false;
                        for (let j = 1; j <= 4 && (i + j) < lines.length; j++) {
                            if (lines[i+j].match(/(FilledButton|ElevatedButton|OutlinedButton|TextButton|ElevatedButton\.icon|FilledButton\.icon)/)) {
                                hasButton = true;
                                break;
                            }
                        }
                        if (hasButton) {
                            count++;
                            filesWithIssues.push(`${fullPath.split('lib/')[1]}:${i+1}`);
                        }
                    }
                }
            }
        }
    }

    scanDir(dir);
    return { count, filesWithIssues };
}

const result = findRigidButtonHeights('/Users/mac/Gatekipa/lib');
console.log(`Found ${result.count} instances of rigid height constraints wrapping buttons.`);
console.log('Locations:');
result.filesWithIssues.forEach(f => console.log(' - ' + f));
