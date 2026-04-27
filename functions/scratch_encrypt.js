const AES256 = require('aes-everywhere');
const encrypted = AES256.encrypt('1234', 'test_key');
console.log('Encrypted:', encrypted);
console.log('Length:', encrypted.length);
