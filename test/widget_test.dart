import 'dart:io';

import 'package:denapaona/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

Future<LedgerEntity> addTestEntity(
  LedgerController controller, {
  LedgerType type = LedgerType.shopDebt,
}) async {
  await controller.addEntity(type, 'টেস্ট হিসাব', '01711000000');
  return controller.entities.last;
}

Future<LedgerTransaction> addTestTransaction(
  LedgerController controller, {
  LedgerEntity? entity,
  LedgerType entityType = LedgerType.shopDebt,
  TransactionType type = TransactionType.debt,
  double amount = 100,
  DateTime? date,
}) async {
  final target = entity ?? await addTestEntity(controller, type: entityType);
  await controller.addTransaction(
    entityId: target.id,
    type: type,
    description: 'টেস্ট লেনদেন',
    amount: amount,
    date: date ?? DateTime(2026, 4, 18),
  );
  return controller.transactions.last;
}

void main() {
  testWidgets('shows login screen without demo credentials', (tester) async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_test.db',
    );

    await tester.pumpWidget(
      DenaPaonaApp(
        firebaseReady: false,
        repositoryFactory: () async =>
            LocalLedgerRepository.fromDatabase(database),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('demo@denapaona.local'), findsNothing);
  });

  test('queues local changes while offline', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_queue_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    await controller.addEntity(
      LedgerType.shopDebt,
      'টেস্ট দোকান',
      '০১৭১১',
    );

    expect(controller.pendingSyncCount, greaterThan(0));
    expect(await repository.pendingOperationCount(), 1);

    controller.dispose();
  });

  test('queues imported data for Firestore collections and snapshot', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_import_queue_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    await addTestTransaction(controller);
    final exported = controller.exportJson();
    await controller.importJson(exported);

    expect(controller.pendingSyncCount, greaterThan(0));

    controller.dispose();
  });

  test('keeps pending local entity update over older remote copy', () {
    final oldTime = DateTime(2026, 1);
    final newTime = DateTime(2026, 2);
    final local = LedgerEntity(
      id: 'entity_1',
      type: LedgerType.shopDebt,
      name: 'লোকাল দোকান',
      phone: '১',
      createdAt: oldTime,
      updatedAt: newTime,
    );
    final remote = LedgerEntity(
      id: 'entity_1',
      type: LedgerType.shopDebt,
      name: 'রিমোট দোকান',
      phone: '২',
      createdAt: oldTime,
      updatedAt: oldTime,
    );

    final resolved = resolveEntityConflicts(
      local: [local],
      remote: [remote],
      pendingUpserts: {'entity_1'},
      pendingDeletes: {},
    );

    expect(resolved.single.name, 'লোকাল দোকান');
  });

  test('remote delete wins unless local delete or upsert is pending', () {
    final time = DateTime(2026, 1);
    final local = LedgerEntity(
      id: 'entity_1',
      type: LedgerType.shopDebt,
      name: 'লোকাল দোকান',
      phone: '১',
      createdAt: time,
      updatedAt: time,
    );

    final resolvedWithoutPending = resolveEntityConflicts(
      local: [local],
      remote: [],
      pendingUpserts: {},
      pendingDeletes: {},
    );
    final resolvedWithPending = resolveEntityConflicts(
      local: [local],
      remote: [],
      pendingUpserts: {'entity_1'},
      pendingDeletes: {},
    );

    expect(resolvedWithoutPending, isEmpty);
    expect(resolvedWithPending.single.id, 'entity_1');
  });

  test('newer transaction wins normal remote conflict', () {
    final oldTime = DateTime(2026, 1);
    final newTime = DateTime(2026, 2);
    final local = LedgerTransaction(
      id: 'tx_1',
      entityId: 'entity_1',
      type: TransactionType.debt,
      description: 'পুরনো',
      amount: 10,
      date: oldTime,
      updatedAt: oldTime,
    );
    final remote = LedgerTransaction(
      id: 'tx_1',
      entityId: 'entity_1',
      type: TransactionType.debt,
      description: 'নতুন',
      amount: 20,
      date: newTime,
      updatedAt: newTime,
    );

    final resolved = resolveTransactionConflicts(
      local: [local],
      remote: [remote],
      pendingUpserts: {},
      pendingDeletes: {},
    );

    expect(resolved.single.description, 'নতুন');
    expect(resolved.single.amount, 20);
  });

  test('updates transaction and queues sync operation', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_update_tx_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final tx = await addTestTransaction(controller);
    await controller.updateTransaction(
      id: tx.id,
      type: tx.type,
      description: 'আপডেটেড লেনদেন',
      amount: 999,
      date: tx.date,
      method: tx.method,
    );

    final updated = controller.transactions.firstWhere((item) => item.id == tx.id);
    expect(updated.description, 'আপডেটেড লেনদেন');
    expect(updated.amount, 999);
    expect(controller.pendingSyncCount, greaterThan(0));

    controller.dispose();
  });

  test('deletes transaction and queues delete operation', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_delete_tx_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final tx = await addTestTransaction(controller);
    await controller.deleteTransaction(tx.id);

    expect(controller.transactions.any((item) => item.id == tx.id), isFalse);
    expect(controller.pendingSyncCount, greaterThan(0));

    controller.dispose();
  });

  test('builds combined debt detail timeline with payments by date', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_detail_timeline_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final entity = await addTestEntity(controller);
    await controller.addTransaction(
      entityId: entity.id,
      type: TransactionType.debt,
      description: 'পুরনো দেনা',
      amount: 300,
      date: DateTime(2026, 4, 10),
    );
    await controller.addTransaction(
      entityId: entity.id,
      type: TransactionType.payment,
      description: 'মাঝের পরিশোধ',
      amount: 100,
      date: DateTime(2026, 4, 12),
      method: 'নগদ',
    );
    await controller.addTransaction(
      entityId: entity.id,
      type: TransactionType.debt,
      description: 'নতুন দেনা',
      amount: 200,
      date: DateTime(2026, 4, 14),
    );

    final timeline = controller.transactionsFor(entity.id);

    expect(timeline.map((tx) => tx.description), [
      'নতুন দেনা',
      'মাঝের পরিশোধ',
      'পুরনো দেনা',
    ]);
    expect(timeline.map((tx) => tx.type), [
      TransactionType.debt,
      TransactionType.payment,
      TransactionType.debt,
    ]);

    controller.dispose();
  });

  test('saves detailed multi-item transaction with auto total', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_detail_tx_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final entity = await addTestEntity(controller);
    final entityId = entity.id;
    final items = const [
      DetailItem(name: 'চাল', amount: 500),
      DetailItem(name: 'তেল', amount: 250),
    ];
    await controller.addTransaction(
      entityId: entityId,
      type: TransactionType.debt,
      description: 'বাজার',
      amount: detailItemsTotal(items),
      date: DateTime(2026, 4, 18),
      subItems: items,
    );

    final saved = controller.transactions.last;
    expect(saved.amount, 750);
    expect(saved.subItems.length, 2);
    expect(saved.subItems.first.name, 'চাল');
    expect(controller.pendingSyncCount, greaterThan(0));

    controller.dispose();
  });

  test('updates detailed transaction items and total', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_detail_update_tx_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final tx = await addTestTransaction(controller);
    final items = const [
      DetailItem(name: 'ডাল', amount: 120),
      DetailItem(name: 'মসলা', amount: 80),
    ];
    await controller.updateTransaction(
      id: tx.id,
      type: tx.type,
      description: 'ডিটেইল আপডেট',
      amount: detailItemsTotal(items),
      date: tx.date,
      method: tx.method,
      subItems: items,
    );

    final updated = controller.transactions.firstWhere((item) => item.id == tx.id);
    expect(updated.amount, 200);
    expect(updated.subItems.map((item) => item.name), ['ডাল', 'মসলা']);

    controller.dispose();
  });

  test('imports backup from JSON file', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_file_import_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    await addTestTransaction(controller);
    final exported = controller.exportJson();
    final directory = await Directory.systemTemp.createTemp('denapaona_test');
    final file = File('${directory.path}/backup.json');
    await file.writeAsString(exported);

    await controller.importJsonFile(file);

    expect(controller.entities, isNotEmpty);
    expect(controller.transactions, isNotEmpty);
    expect(controller.pendingSyncCount, greaterThan(0));

    controller.dispose();
    await directory.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('builds report module totals and top balances', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_report_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final shop = await addTestEntity(controller, type: LedgerType.shopDebt);
    await addTestTransaction(controller, entity: shop, amount: 400);
    final receivable =
        await addTestEntity(controller, type: LedgerType.receivable);
    await addTestTransaction(controller, entity: receivable, amount: 700);

    expect(controller.moduleTotals[LedgerType.shopDebt], greaterThan(0));
    expect(controller.moduleTotals[LedgerType.receivable], greaterThan(0));
    expect(controller.topEntities(limit: 2), hasLength(2));

    controller.dispose();
  });

  test('builds six month transaction trend buckets', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_monthly_report_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    await addTestTransaction(
      controller,
      amount: 500,
      date: DateTime.now().subtract(const Duration(days: 10)),
    );
    final monthly = controller.monthlyTransactionTotals();

    expect(monthly, hasLength(6));
    expect(monthly.values.fold<double>(0, (sum, value) => sum + value), greaterThan(0));

    controller.dispose();
  });

  test('sets and completes entity reminder', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_reminder_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();
    final entity = await addTestEntity(controller);
    await controller.updateReminder(
      entity,
      reminderAt: DateTime.now().subtract(const Duration(days: 1)),
      reminderNote: 'টাকা চাইতে হবে',
    );

    expect(controller.activeReminders, hasLength(1));
    expect(controller.overdueReminders, hasLength(1));
    expect(controller.pendingSyncCount, greaterThan(0));

    await controller.completeReminder(entity);

    expect(controller.activeReminders, isEmpty);
    expect(entity.reminderDone, isTrue);

    controller.dispose();
  });

  test('builds reminder message and normalizes phone', () {
    final entity = LedgerEntity(
      id: 'entity_sms',
      type: LedgerType.receivable,
      name: 'করিম',
      phone: '+880 1711-222333',
      createdAt: DateTime(2026, 1),
      updatedAt: DateTime(2026, 1),
      reminderAt: DateTime(2026, 4, 18),
      reminderNote: 'আজ টাকা দেওয়ার কথা',
    );

    final message = reminderMessageFor(entity: entity, balance: 1250);

    expect(message, contains(entity.name));
    expect(message, contains('1,250'));
    expect(message, contains(entity.reminderNote));
    expect(normalizedPhoneForIntent(entity.phone), '+8801711222333');
  });

  test('persists dark mode preference locally', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_theme_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);

    expect(await repository.getThemeMode(), ThemeMode.light);

    await repository.setThemeMode(ThemeMode.dark);

    expect(await repository.getThemeMode(), ThemeMode.dark);
    await repository.close();
  });

  test('toggles app theme from controller', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'denapaona_controller_theme_test.db',
    );
    final repository = LocalLedgerRepository.fromDatabase(database);
    final controller = LedgerController(
      firebaseReady: false,
      repositoryFactory: () async => repository,
    );

    await controller.boot();

    expect(controller.themeMode, ThemeMode.light);

    await controller.toggleTheme();

    expect(controller.themeMode, ThemeMode.dark);
    expect(await repository.getThemeMode(), ThemeMode.dark);

    controller.dispose();
  });

  test('ships production Firestore security rules', () {
    final rules = File('firestore.rules').readAsStringSync();
    final firebaseConfig = File('firebase.json').readAsStringSync();

    expect(firebaseConfig, contains('"rules": "firestore.rules"'));
    expect(rules, contains('request.auth.uid == userId'));
    expect(rules, contains('match /users/{userId}'));
    expect(rules, contains('match /entities/{entityId}'));
    expect(rules, contains('match /transactions/{transactionId}'));
    expect(rules, contains("snapshotId == 'latest'"));
    expect(rules, contains('allow read, write: if false'));
  });
}
