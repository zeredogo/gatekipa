import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../cards/providers/card_provider.dart';

class TrialData {
  final String name;
  final double savedAmount;
  final String date;
  final bool autoBlocked;
  const TrialData(this.name, this.savedAmount, this.date, this.autoBlocked);
}

class Milestone {
  final String title;
  final String sub;
  final bool achieved;
  const Milestone(this.title, this.sub, this.achieved);
}

class ServiceItem {
  final String name;
  final double cost;
  final String category;
  final String usage;
  final int efficiency;
  final IconData icon;
  final Color color;

  const ServiceItem(this.name, this.cost, this.category, this.usage,
      this.efficiency, this.icon, this.color);
}

class AnalyticsModel {
  final double recoveredCapital;
  final double totalSpend;
  final int txCount;
  final int chargesBlocked;
  final int trialCardsCount;
  final int monthsActive;
  final List<double> trendValues;
  final List<String> trendMonths;
  final List<TrialData> blockedTrials;
  final List<Milestone> milestones;
  final List<ServiceItem> topServices;
  final int protectionScore;

  const AnalyticsModel({
    required this.recoveredCapital,
    required this.totalSpend,
    required this.txCount,
    required this.chargesBlocked,
    required this.trialCardsCount,
    required this.monthsActive,
    required this.trendValues,
    required this.trendMonths,
    required this.blockedTrials,
    required this.milestones,
    required this.topServices,
    required this.protectionScore,
  });
}

final analyticsProvider = Provider<AsyncValue<AnalyticsModel>>((ref) {
  final transactionsAsync = ref.watch(transactionsProvider);
  final cardsAsync = ref.watch(cardsProvider);

  if (transactionsAsync.isLoading || cardsAsync.isLoading) {
    return const AsyncValue.loading();
  }

  if (transactionsAsync.hasError) {
    return AsyncValue.error(transactionsAsync.error!, transactionsAsync.stackTrace!);
  }
  
  if (cardsAsync.hasError) {
    return AsyncValue.error(cardsAsync.error!, cardsAsync.stackTrace!);
  }

  final transactions = transactionsAsync.value ?? [];
  final cards = cardsAsync.value ?? [];

  double recoveredCapital = 0;
  double totalSpend = 0;
  int chargesBlocked = 0;
  int txCount = transactions.length;
  List<TrialData> blockedTrials = [];

  for (final tx in transactions) {
    if (tx.isDeclined) {
      recoveredCapital += tx.amount;
      chargesBlocked++;

      final isTrialCard = cards.any((c) => c.id == tx.cardId && c.isTrial);
      if (isTrialCard) {
        blockedTrials.add(TrialData(
          tx.merchantName,
          tx.amount,
          "${tx.timestamp.day.toString().padLeft(2, '0')} ${_monthStr(tx.timestamp.month)} ${tx.timestamp.year}",
          true,
        ));
      }
    } else if (tx.isApproved) {
      totalSpend += tx.amount;
    }
  }

  // Calculate top services
  final merchants = <String, double>{};
  final merchantCount = <String, int>{};
  for (final tx in transactions) {
     if (tx.isApproved) {
        merchants[tx.merchantName] = (merchants[tx.merchantName] ?? 0) + tx.amount;
        merchantCount[tx.merchantName] = (merchantCount[tx.merchantName] ?? 0) + 1;
     }
  }
  final topServices = merchants.entries.map((e) {
      final name = e.key;
      final cost = e.value;
      final count = merchantCount[name] ?? 1;
      
      int eff = 80;
      Color col = AppColors.primary;
      IconData icon = Icons.payment_rounded;
      
      // Heuristic for demonstration
      if (count == 1 && cost > 5000) {
        eff = 35;
      } else if (count > 3 && cost < 2000) {
        eff = 92;
      } else {
        eff = (count * 15).clamp(20, 95);
      }
      
      if (eff < 40) {
        col = AppColors.error;
      } else if (eff < 75) {
        col = const Color(0xFFFF6B35);
      } else {
        col = AppColors.tertiary;
      }
      
      return ServiceItem(name, cost, 'Subscription', '$count charges', eff, icon, col);
  }).toList();
  topServices.sort((a,b) => b.cost.compareTo(a.cost));

  // Sort blocked trials by date descending
  blockedTrials.sort((a, b) => b.date.compareTo(a.date));

  int trialCardsCount = cards.where((c) => c.isTrial).length;

  int monthsActive = 1;
  if (cards.isNotEmpty) {
    final earliestDate = cards.map((c) => c.createdAtDate).reduce((a, b) => a.isBefore(b) ? a : b);
    monthsActive = DateTime.now().difference(earliestDate).inDays ~/ 30;
    if (monthsActive < 1) monthsActive = 1;
  }

  // Trend data: last 7 days calendar dates for better visualization
  final now = DateTime.now();
  List<double> trendValues = List.filled(7, 0.0);
  List<String> trendMonths = [];
  
  for (int i = 6; i >= 0; i--) {
    final dayDate = now.subtract(Duration(days: i));
    trendMonths.add("${dayDate.day} ${_monthStr(dayDate.month)}");
  }

  for (final tx in transactions) {
    // Collect both successful and declined transactions so the chart is never empty
    // even for new clients or non-declined test data.
    final daysAgo = now.difference(tx.timestamp).inDays;
    if (daysAgo >= 0 && daysAgo < 7) {
      trendValues[6 - daysAgo] += tx.amount;
    }
  }

  int protectionScore = 100;
  if (chargesBlocked == 0 && cards.isNotEmpty) {
      protectionScore = 80;
  }

  final milestones = [
    Milestone('First Block!', 'Any charge blocked', chargesBlocked > 0),
    Milestone('Trial Slayer', '5 trial charges blocked', blockedTrials.length >= 5),
    Milestone('₦10k Vault', '₦10,000 recovered', recoveredCapital >= 10000),
    Milestone('Sentinel', '₦50,000 recovered', recoveredCapital >= 50000),
    Milestone('Guardian', '100 charges blocked', chargesBlocked >= 100),
  ];

  return AsyncValue.data(AnalyticsModel(
    recoveredCapital: recoveredCapital,
    totalSpend: totalSpend,
    txCount: txCount,
    chargesBlocked: chargesBlocked,
    trialCardsCount: trialCardsCount,
    monthsActive: monthsActive,
    trendValues: trendValues,
    trendMonths: trendMonths,
    blockedTrials: blockedTrials,
    milestones: milestones,
    topServices: topServices,
    protectionScore: protectionScore,
  ));
});

String _monthStr(int month) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (month >= 1 && month <= 12) return months[month - 1];
  return '';
}
