// lib/features/search/providers/search_provider.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../accounts/models/account_model.dart';
import '../../cards/models/virtual_card_model.dart';

class SearchResult {
  final List<AccountModel> accounts;
  final List<VirtualCardModel> cards;

  const SearchResult({required this.accounts, required this.cards});

  static const empty = SearchResult(accounts: [], cards: []);
}

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<SearchResult>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return SearchResult.empty;

  try {
    final callable = FirebaseFunctions.instance.httpsCallable('searchEntities');
    final result = await callable.call({'query': query});

    final data = result.data as Map<String, dynamic>;

    final accounts = (data['accounts'] as List? ?? [])
        .map((a) => AccountModel(
              id: a['id'] ?? '',
              ownerUserId: a['owner_user_id'] ?? '',
              name: a['name'] ?? '',
              type: a['type'] ?? 'personal',
              createdAt: a['created_at'] ?? 0,
            ))
        .toList();

    final cards = (data['cards'] as List? ?? [])
        .map((c) => VirtualCardModel(
              id: c['id'] ?? '',
              accountId: c['account_id'] ?? '',
              name: c['name'] ?? '',
              status: c['status'] ?? 'active',
              isTrial: c['is_trial'] ?? false,
              createdAt: c['created_at'] ?? 0,
            ))
        .toList();

    return SearchResult(accounts: accounts, cards: cards);
  } catch (e) {
    return SearchResult.empty;
  }
});
