/**
 * PRODUCTION-READY CLOUD FUNCTIONS
 * Strict PRD Implementation
 */

const { setGlobalOptions } = require("firebase-functions/v2");
// Allows standard Cloud Run scaling on the Blaze plan up to a sustainable cap
// Setting cpu to 0.16 to prevent exceeding regions total allowable CPU quota during multi-function deployment
setGlobalOptions({ 
  maxInstances: 1, 
  memory: "256MiB", 
  cpu: 0.16, 
  enforceAppCheck: false,
  secrets: ["SUDO_API_KEY", "RESEND_API_KEY", "SAFEHAVEN_CLIENT_ID", "SAFEHAVEN_PRIVATE_KEY", "SUDO_WEBHOOK_SECRET", "SAFEHAVEN_WEBHOOK_SECRET", "DATABASE_URL"] 
});

const { onUserCreated, purchasePlanFromVault, resendVerificationEmail, requestPasswordReset, checkMigrationStatus } = require("./services/authService");
const { createAccount, inviteTeamMember, renameAccount, deleteAccount, switchActiveAccount, removeTeamMember } = require("./services/accountService");
const { createVirtualCard, toggleCardStatus, freezeAllCards, renameCard, adminGlobalFreeze, sendCardNotification } = require("./services/cardService");
const { createRule, deleteRule, adminSimulateRuleEngine } = require("./services/ruleService");
const { processTransaction, fundCard, toggleSpendingLock } = require("./services/transactionService");
const { searchEntities } = require("./services/searchService");
const { detectSubscriptions } = require("./services/detectService");
const { createVaultAccount, requestWithdrawal, recreateVaultAccount, initiateVaultVerification } = require("./services/walletService");
const { verifyBvn, verifyKyc, validateIdentity, qoreidWebhook } = require("./services/kycService");

const { deleteUserAccount, setTransactionPin } = require("./services/userService");
// Bridgecard removed
const { integritySweep, pollMissingWebhooks, aggregateSystemStats } = require("./services/reconciliationCron");
const { reconciliationDispatcher, processReconciliationBatch } = require("./services/reconciliationDispatcher");
const { scanSubscriptionPatterns, sendRenewalReminders } = require("./services/subscriptionCron");
const { expirationCron } = require("./services/expirationCron");
const { ghostCardSweeper } = require("./services/ghostCardSweeper");
const { adminSetSystemMode, adminGetSystemMode, adminInitializeDatabase } = require("./services/systemService");
const { getUserAnalytics } = require("./services/analyticsService");


// 1. Auth / User Lifecycle
exports.onUserCreated = onUserCreated;
exports.purchasePlanFromVault = purchasePlanFromVault;
exports.resendVerificationEmail = resendVerificationEmail;
exports.requestPasswordReset = requestPasswordReset;
exports.checkMigrationStatus = checkMigrationStatus;
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
exports.adminInitializeDatabase = adminInitializeDatabase;

// 8. Wallet Operations
exports.createVaultAccount = createVaultAccount;
exports.recreateVaultAccount = recreateVaultAccount;
exports.initiateVaultVerification = initiateVaultVerification;
exports.requestWithdrawal = requestWithdrawal;

const { safehavenWebhook } = require("./services/safehavenService");
exports.safehavenWebhook = safehavenWebhook;

// 9. KYC / Identity Verification
exports.verifyBvn = verifyBvn;
exports.verifyKyc = verifyKyc;
exports.validateIdentity = validateIdentity;



exports.getUserAnalytics = getUserAnalytics;

// 11. Sudo — Real Virtual Card Issuing
const { sudoWebhook, migratePendingSudoCards, migrateUSDBridgecardsToSudo, createSudoCard, revealCardDetails, fundSudoCard } = require("./services/sudoService");
exports.sudoWebhook = sudoWebhook;
exports.migratePendingSudoCards = migratePendingSudoCards;
exports.migrateUSDBridgecardsToSudo = migrateUSDBridgecardsToSudo;
exports.createSudoCard = createSudoCard;
exports.fundSudoCard = fundSudoCard;

exports.revealCardDetails = revealCardDetails;


// 12. User Account Management
exports.deleteUserAccount = deleteUserAccount;
exports.setTransactionPin = setTransactionPin;

