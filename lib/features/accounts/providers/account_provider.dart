// lib/features/accounts/providers/account_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/accounts/models/account_model.dart';

import 'package:rxdart/rxdart.dart';

// ── Member Account IDs Context ───────────────────────────────────────────────────
final memberAccountIdsProvider = StreamProvider<List<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);
  
  return FirebaseFirestore.instance
      .collection('team_members')
      .where('user_id', isEqualTo: user.uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.data()['account_id'] as String).toList());
});

// ── Accounts Stream ─────────────────────────────────────────────────────────────
// Reads accounts where this user is the owner OR is a team member.
// Step 1: Get team_member docs for this user to get account_ids
// Step 2: Union with accounts where owner_user_id == uid
final accountsStreamProvider = StreamProvider<List<AccountModel>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  final memberAccountIds = ref.watch(memberAccountIdsProvider).valueOrNull ?? [];

  final ownedStream = FirebaseFirestore.instance
      .collection('accounts')
      .where('owner_user_id', isEqualTo: user.uid)
      .snapshots()
      .map((snap) => snap.docs.map((d) => AccountModel.fromFirestore(d)).toList());

  if (memberAccountIds.isEmpty) {
    return ownedStream.map((list) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  final chunks = <List<String>>[];
  for (var i = 0; i < memberAccountIds.length; i += 10) {
    chunks.add(memberAccountIds.sublist(i, i + 10 > memberAccountIds.length ? memberAccountIds.length : i + 10));
  }
  
  final memberStreams = chunks.map((chunk) {
    return FirebaseFirestore.instance
        .collection('accounts')
        .where(FieldPath.documentId, whereIn: chunk)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AccountModel.fromFirestore(d)).toList());
  });

  return CombineLatestStream.list<List<AccountModel>>([ownedStream, ...memberStreams]).map((listOfLists) {
    final allAccounts = listOfLists.expand((element) => element).toList();
    final map = <String, AccountModel>{};
    for (var a in allAccounts) {
      map[a.id] = a;
    }
    final deduplicated = map.values.toList();
    deduplicated.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return deduplicated;
  });
});

// ── Active Account Context ──────────────────────────────────────────────────────
class ActiveAccountNotifier extends StateNotifier<String?> {
  ActiveAccountNotifier() : super(null);

  void setActiveAccount(String accountId) => state = accountId;
}

final activeAccountIdProvider =
    StateNotifierProvider<ActiveAccountNotifier, String?>((ref) {
  return ActiveAccountNotifier();
});

final activeAccountProvider = Provider<AccountModel?>((ref) {
  final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
  if (accounts.isEmpty) return null;
  final activeId = ref.watch(activeAccountIdProvider);
  if (activeId != null) {
    try {
      return accounts.firstWhere((a) => a.id == activeId);
    } catch (_) {}
  }
  return accounts.first;
});

// ── Account Notifier — all mutations go through Cloud Functions ─────────────────
class AccountNotifier extends StateNotifier<AsyncValue<void>> {
  AccountNotifier() : super(const AsyncValue.data(null));

  Future<String?> createAccount({required String name, required String type}) async {
    state = const AsyncValue.loading();
    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('createAccount').call({
        'name': name,
        'type': type,
      });

      state = const AsyncValue.data(null);
      final dataMap = result.data as Map<dynamic, dynamic>;
      return dataMap['accountId']?.toString();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  Future<bool> renameAccount({required String accountId, required String newName}) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('renameAccount').call({
        'account_id': accountId,
        'new_name': newName,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> deleteAccount({required String accountId, bool confirmDelete = false}) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteAccount').call({
        'account_id': accountId,
        if (confirmDelete) 'confirm_delete': true,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }

  }

  Future<bool> switchActiveAccount({required String accountId}) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('switchActiveAccount').call({
        'account_id': accountId,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<String?> inviteTeamMember({
    required String accountId,
    required String targetUserId,
    required String role,
    double? spendLimit,
  }) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('inviteTeamMember').call({
        'account_id': accountId,
        'target_user_id': targetUserId,
        'role': role,
        if (spendLimit != null) 'spend_limit': spendLimit,
      });
      state = const AsyncValue.data(null);
      return null;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      if (e is FirebaseFunctionsException) {
        return e.message;
      }
      return e.toString();
    }
  }
}

final accountNotifierProvider =
    StateNotifierProvider<AccountNotifier, AsyncValue<void>>((ref) {
  return AccountNotifier();
});
