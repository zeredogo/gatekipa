/**
 * PRODUCTION-READY CLOUD FUNCTIONS
 * Strict PRD Implementation
 */

const { setGlobalOptions } = require("firebase-functions/v2");
// Allows standard Cloud Run scaling on the Blaze plan up to a sustainable cap
// Setting cpu to 0.16 to prevent exceeding regions total allowable CPU quota during multi-function deployment
setGlobalOptions({ maxInstances: 1, memory: "256MiB", cpu: 0.16 });

const { onUserCreated } = require("./services/authService");
const { createAccount, inviteTeamMember, renameAccount, deleteAccount, switchActiveAccount, removeTeamMember } = require("./services/accountService");
const { createVirtualCard, toggleCardStatus, activateKillSwitch, renameCard } = require("./services/cardService");
const { createRule, deleteRule } = require("./services/ruleService");
const { processTransaction } = require("./services/transactionService");
const { searchEntities } = require("./services/searchService");
const { detectSubscriptions } = require("./services/detectService");
const { fundWallet, withdrawFunds, createVaultAccount } = require("./services/walletService");
const { verifyBvn, verifyKyc } = require("./services/kycService");
const { verifyPaystackPayment, paystackWebhook } = require("./services/paystackService");
const {
  registerCardholder,
  createBridgecard,
  fundBridgecard,
  freezeBridgecard,
  bridgecardWebhook,
} = require("./services/bridgecardService");


// 1. Auth / User Lifecycle
exports.onUserCreated = onUserCreated;

// 2. Account Management
exports.createAccount = createAccount;
exports.inviteTeamMember = inviteTeamMember;
exports.renameAccount = renameAccount;
exports.deleteAccount = deleteAccount;
exports.switchActiveAccount = switchActiveAccount;
exports.removeTeamMember = removeTeamMember;

// 3. Card Management
exports.createVirtualCard = createVirtualCard;
exports.toggleCardStatus = toggleCardStatus;
exports.activateKillSwitch = activateKillSwitch;
exports.renameCard = renameCard;

// 4. Rule Engine Configuration
exports.createRule = createRule;
exports.deleteRule = deleteRule;

// 5. Transaction & Evaluation Core
exports.processTransaction = processTransaction;

// 6. Search Service
exports.searchEntities = searchEntities;

// 7. Device Detection
exports.detectSubscriptions = detectSubscriptions;

// 8. Wallet Operations
exports.fundWallet = fundWallet;
exports.withdrawFunds = withdrawFunds;
exports.createVaultAccount = createVaultAccount;

// 9. KYC / Identity Verification
exports.verifyBvn = verifyBvn;
exports.verifyKyc = verifyKyc;

// 10. Payment Verification
exports.verifyPaystackPayment = verifyPaystackPayment;
exports.paystackWebhook = paystackWebhook;

// 11. Bridgecard — Real NGN Virtual Card Issuing
exports.registerCardholder = registerCardholder;
exports.createBridgecard = createBridgecard;
exports.fundBridgecard = fundBridgecard;
exports.freezeBridgecard = freezeBridgecard;
exports.bridgecardWebhook = bridgecardWebhook;
