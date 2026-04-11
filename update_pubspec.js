const fs = require('fs');
const content = fs.readFileSync('pubspec.yaml', 'utf8');
const newContent = content.replace('firebase_core: ^3.6.0', 'firebase_core: ^3.6.0\n  firebase_app_check: ^0.3.1+3');
fs.writeFileSync('pubspec.yaml', newContent);
