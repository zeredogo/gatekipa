// lib/core/constants/routes.dart
class Routes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String emailAuth = '/email-auth';
  static const String phoneAuth = '/phone-auth';
  // Alias for phoneAuth (used in sign-out redirects)
  static const String phone = '/phone-auth';
  static const String otp = '/otp';
  static const String emailVerifyPending = '/email-verify-pending';
  static const String kyc = '/kyc';
  static const String shell = '/home';
  static const String dashboard = '/home/dashboard';
  static const String wallet = '/home/wallet';
  static const String addFunds = '/home/wallet/add-funds';
  static const String cards = '/home/cards';
  static const String cardCreation = '/home/cards/create';
  static const String cardDetail = '/home/cards/:cardId';
  static const String detect = '/home/detect';
  static const String detectedSubscriptions = '/home/detect/subscriptions';
  static const String notifications = '/home/notifications';
  static const String notificationDetail = '/home/notifications/:notifId';
  static const String insights = '/home/insights';
  static const String efficiencyPortfolio = '/home/insights/efficiency';
  static const String savingsDeepDive = '/home/insights/savings';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String accounts = '/home/accounts';
  static const String search = '/home/search';
}
