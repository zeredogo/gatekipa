// lib/core/constants/app_constants.dart

class AppConstants {
  // App info
  static const String appName = 'Gatekipa';
  static const String appTagline = 'Stop Unwanted Charges';
  static const String appVersion = '1.0.0';
  static const String currencySymbol = '₦';
  static const String currencyCode = 'NGN';

  // Premium pricing
  static const double premiumPriceMonthly = 999;
  static const String premiumPriceLabel = '₦999/mo';

  // Paystack — live production key
  // Get yours at: https://dashboard.paystack.com/#/settings/developers
  static const String paystackPublicKey = 'pk_live_202db48004edd761da323d1d2d8820ed55f3b569';

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String cardsCollection = 'cards';
  static const String transactionsCollection = 'transactions';
  static const String notificationsCollection = 'notifications';
  static const String subscriptionsCollection = 'subscriptions';
  static const String walletDoc = 'wallet';

  // Card Types
  static const String cardTypeTrial = 'trial';
  static const String cardTypeSubscription = 'subscription';
  static const String cardTypeCustom = 'custom';

  // Card Status
  static const String cardStatusActive = 'active';
  static const String cardStatusBlocked = 'blocked';
  static const String cardStatusExpired = 'expired';

  // Transaction Status
  static const String txStatusApproved = 'approved';
  static const String txStatusBlocked = 'blocked';
  static const String txStatusPending = 'pending';

  // Notification Types
  static const String notifTypeBlocked = 'blocked';
  static const String notifTypeUpcoming = 'upcoming';
  static const String notifTypeSystem = 'system';
  static const String notifTypeTransaction = 'transaction';

  // Trial card defaults
  static const int trialMaxCharges = 1;
  static const int trialExpiryDays = 30;
  static const double defaultMaxAmount = 50000; // ₦50,000

  // Transaction fee range
  static const double txFeeMin = 50;
  static const double txFeeMax = 100;

  // Subscription categories
  static const String catStreaming = 'Entertainment & Streaming';
  static const String catSaas = 'SaaS & Productivity';
  static const String catUtilities = 'Utilities & Infrastructure';
  static const String catCloud = 'Cloud Storage';
  static const String catMusic = 'Audio Streaming';
}
