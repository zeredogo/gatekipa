const AES256 = require('aes-everywhere');
const encrypted = AES256.encrypt('1234', undefined);
console.log('Encrypted with undefined:', encrypted);
console.log('Length:', encrypted.length);
