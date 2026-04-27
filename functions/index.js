/**
 * PRODUCTION-READY CLOUD FUNCTIONS
 * Strict PRD Implementation
 */

const { setGlobalOptions } = require("firebase-functions/v2");
// Allows standard Cloud Run scaling on the Blaze plan up to a sustainable cap
// Setting cpu to 0.16 to prevent exceeding regions total allowable CPU quota during multi-function deployment
setGlobalOptions({ maxInstances: 1, memory: "256MiB", cpu: 0.16, enforceAppCheck: false });

const { onUserCreated, purchasePlan, purchasePlanFromVault, resendVerificationEmail, requestPasswordReset } = require("./services/authService");
const { createAccount, inviteTeamMember, renameAccount, deleteAccount, switchActiveAccount, removeTeamMember } = require("./services/accountService");
const { createVirtualCard, toggleCardStatus, freezeAllCards, renameCard, adminGlobalFreeze, sendCardNotification } = require("./services/cardService");
const { createRule, deleteRule, adminSimulateRuleEngine } = require("./services/ruleService");
const { processTransaction, fundCard, toggleSpendingLock } = require("./services/transactionService");
const { searchEntities } = require("./services/searchService");
const { detectSubscriptions } = require("./services/detectService");
const { createVaultAccount, requestWithdrawal, recreateVaultAccount } = require("./services/walletService");
const { verifyBvn, verifyKyc, qoreidWebhook } = require("./services/kycService");
const { verifyPaystackPayment, paystackWebhook } = require("./services/paystackService");
const { deleteUserAccount, initiatePremiumUpgrade, verifyPremiumPayment, setTransactionPin } = require("./services/userService");
const {
  registerCardholder,
  createBridgecard,
  fundBridgecard,
  freezeBridgecard,
  adminFreezeCard,
  bridgecardWebhook,
  revealCardDetails,
  getCardOtp,
} = require("./services/bridgecardService");
const { integritySweep, pollMissingWebhooks, aggregateSystemStats } = require("./services/reconciliationCron");
const { reconciliationDispatcher, processReconciliationBatch } = require("./services/reconciliationDispatcher");
const { scanSubscriptionPatterns, sendRenewalReminders } = require("./services/subscriptionCron");
const { expirationCron } = require("./services/expirationCron");
const { ghostCardSweeper } = require("./services/ghostCardSweeper");
const { adminSetSystemMode, adminGetSystemMode } = require("./services/systemService");
const { getUserAnalytics } = require("./services/analyticsService");


// 1. Auth / User Lifecycle
exports.onUserCreated = onUserCreated;
exports.purchasePlan  = purchasePlan;
exports.purchasePlanFromVault = purchasePlanFromVault;
exports.resendVerificationEmail = resendVerificationEmail;
exports.requestPasswordReset = requestPasswordReset;
exports.setTransactionPin = setTransactionPin;

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
exports.freezeAllCards = freezeAllCards;
exports.renameCard = renameCard;
exports.adminGlobalFreeze = adminGlobalFreeze;
exports.sendCardNotification = sendCardNotification;

// 3.5. Notifications
const { adminBroadcastMessage, adminSendInAppNotification } = require("./services/notificationService");
exports.adminBroadcastMessage = adminBroadcastMessage;
exports.adminSendInAppNotification = adminSendInAppNotification;

// 4. Rule Engine Configuration
exports.createRule = createRule;
exports.deleteRule = deleteRule;
exports.adminSimulateRuleEngine = adminSimulateRuleEngine;

// 5. Transaction & Evaluation Core
exports.processTransaction = processTransaction;
exports.fundCard = fundCard;
exports.toggleSpendingLock = toggleSpendingLock;

// 6. Search Service
exports.searchEntities = searchEntities;

// 7. Device Detection
exports.detectSubscriptions = detectSubscriptions;

// 8. CRON & Automations
exports.integritySweep            = integritySweep;
exports.pollMissingWebhooks       = pollMissingWebhooks;
exports.aggregateSystemStats      = aggregateSystemStats;
exports.reconciliationDispatcher  = reconciliationDispatcher;
exports.processReconciliationBatch = processReconciliationBatch;
exports.ghostCardSweeper          = ghostCardSweeper;
exports.scanSubscriptionPatterns  = scanSubscriptionPatterns;
exports.sendRenewalReminders      = sendRenewalReminders;
exports.expirationCron            = expirationCron;

// 9. System Mode Management (Admin Only)
exports.adminSetSystemMode = adminSetSystemMode;
exports.adminGetSystemMode = adminGetSystemMode;

// 8. Wallet Operations
exports.createVaultAccount = createVaultAccount;
exports.recreateVaultAccount = recreateVaultAccount;
exports.requestWithdrawal = requestWithdrawal;

// 9. KYC / Identity Verification
exports.verifyBvn = verifyBvn;
exports.verifyKyc = verifyKyc;
exports.qoreidWebhook = qoreidWebhook;

// 10. Payment Verification
exports.verifyPaystackPayment = verifyPaystackPayment;
exports.paystackWebhook = paystackWebhook;

// 11. Analytics
exports.getUserAnalytics = getUserAnalytics;

// 11. Bridgecard — Real NGN Virtual Card Issuing
exports.registerCardholder = registerCardholder;
exports.createBridgecard = createBridgecard;
exports.fundBridgecard = fundBridgecard;
exports.freezeBridgecard = freezeBridgecard;
exports.adminFreezeCard = adminFreezeCard;
exports.bridgecardWebhook = bridgecardWebhook;
exports.revealCardDetails = revealCardDetails;
exports.getCardOtp = getCardOtp;

// 12. User Account Management
exports.deleteUserAccount = deleteUserAccount;
exports.initiatePremiumUpgrade = initiatePremiumUpgrade;
exports.verifyPremiumPayment = verifyPremiumPayment;
