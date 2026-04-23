const fs = require('fs');
let code = fs.readFileSync('functions/services/paystackService.js', 'utf8');

// Use Paystack's data.reference instead of client-provided reference to avoid any encoding mismatches
code = code.replace(
  /const idempotencyRef = db\s*\.collection\("users"\)\s*\.doc\(uid\)\s*\.collection\("funding_history"\)\s*\.doc\(reference\);/g,
  `// Use Paystack's data.reference if available (in verifyPaystackPayment response) to guarantee absolute string parity
    const verifiedRef = typeof data !== "undefined" && data && data.reference ? data.reference : reference;
    const idempotencyRef = db
      .collection("users")
      .doc(uid)
      .collection("funding_history")
      .doc(verifiedRef);`
);

fs.writeFileSync('functions/services/paystackService.js', code);
console.log('Fixed reference checking');
