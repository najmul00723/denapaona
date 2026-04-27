import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast_io.dart' as sembast;
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

const FirebaseOptions _webFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyC7S8lcghGHrGfeZo5NGKJ_w06HQiBJKyU',
  authDomain: 'denapaona01.firebaseapp.com',
  projectId: 'denapaona01',
  storageBucket: 'denapaona01.firebasestorage.app',
  messagingSenderId: '513514862867',
  appId: '1:513514862867:web:47e65e7d17d6ad48f702e6',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  if (!kIsWeb) {
    await ReminderNotificationService.instance.initialize();
  }
  var firebaseReady = false;
  try {
    final app = await Firebase.initializeApp(
      options: kIsWeb ? _webFirebaseOptions : null,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    if (!kIsWeb) {
      await GoogleSignIn.instance.initialize();
    }
    firebaseReady = true;
    debugPrint(
      'Firebase initialized: projectId=${app.options.projectId}, appId=${app.options.appId}',
    );
  } catch (error) {
    firebaseReady = false;
    debugPrint('Firebase initialization failed: $error');
  }

  runApp(DenaPaonaApp(firebaseReady: firebaseReady));
}

class AppColors {
  static const primary = Color(0xFF332A4B);
  static const primaryContainer = Color(0xFF4A4063);
  static const accent = Color(0xFFFDC825);
  static const surface = Color(0xFFEBFDFC);
  static const surfaceLow = Color(0xFFE5F7F6);
  static const surfaceContainer = Color(0xFFDFF1F0);
  static const surfaceHigh = Color(0xFFDAECEB);
  static const white = Color(0xFFFFFFFF);
  static const text = Color(0xFF0E1E1E);
  static const muted = Color(0xFF49454D);
  static const success = Color(0xFF00380E);
  static const successSoft = Color(0xFF9FF79F);
  static const error = Color(0xFFBA1A1A);
  static const errorSoft = Color(0xFFFFDAD6);
}

enum LedgerType { shopDebt, generalDebt, receivable, amanot }

extension LedgerTypeLabel on LedgerType {
  String get title => switch (this) {
    LedgerType.shopDebt => 'দোকান',
    LedgerType.generalDebt => 'সাধারণ দেনা',
    LedgerType.receivable => 'পাওনা',
    LedgerType.amanot => 'আমানত',
  };

  String get totalTitle => switch (this) {
    LedgerType.shopDebt => 'মোট দোকানের দেনা',
    LedgerType.generalDebt => 'মোট সাধারণ দেনা',
    LedgerType.receivable => 'মোট পাওনা',
    LedgerType.amanot => 'মোট আমানত',
  };

  bool get isPositive =>
      this == LedgerType.receivable || this == LedgerType.amanot;

  IconData get icon => switch (this) {
    LedgerType.shopDebt => Icons.storefront_rounded,
    LedgerType.generalDebt => Icons.person_search_rounded,
    LedgerType.receivable => Icons.account_balance_wallet_rounded,
    LedgerType.amanot => Icons.account_balance_rounded,
  };

  static LedgerType fromName(String value) => LedgerType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => LedgerType.shopDebt,
  );
}

enum TransactionType { debt, payment }

enum SyncOperationType {
  upsertEntity,
  deleteEntity,
  upsertTransaction,
  deleteTransaction,
  importSnapshot,
}

enum SyncStatus { pending, synced, failed }

class LedgerEntity {
  LedgerEntity({
    required this.id,
    required this.type,
    required this.name,
    required this.phone,
    required this.createdAt,
    required this.updatedAt,
    this.fatherName = '',
    this.address = '',
    this.reminderAt,
    this.reminderNote = '',
    this.reminderDone = false,
  });

  final String id;
  final LedgerType type;
  String name;
  String fatherName;
  String address;
  String phone;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? reminderAt;
  String reminderNote;
  bool reminderDone;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'fatherName': fatherName,
    'address': address,
    'phone': phone,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'reminderAt': reminderAt?.toIso8601String(),
    'reminderNote': reminderNote,
    'reminderDone': reminderDone,
  };

  factory LedgerEntity.fromJson(Map<String, dynamic> json) => LedgerEntity(
    id: json['id'] as String,
    type: LedgerTypeLabel.fromName(json['type'] as String? ?? ''),
    name: json['name'] as String? ?? '',
    fatherName: json['fatherName'] as String? ?? '',
    address: json['address'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
    reminderNote: json['reminderNote'] as String? ?? '',
    reminderDone: json['reminderDone'] as bool? ?? false,
  );
}

class LedgerTransaction {
  LedgerTransaction({
    required this.id,
    required this.entityId,
    required this.type,
    required this.description,
    required this.amount,
    required this.date,
    required this.updatedAt,
    this.method = 'নগদ',
    this.subItems = const [],
  });

  final String id;
  final String entityId;
  final TransactionType type;
  final String description;
  final double amount;
  final DateTime date;
  final DateTime updatedAt;
  final String method;
  final List<DetailItem> subItems;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'type': type.name,
    'description': description,
    'amount': amount,
    'date': date.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'method': method,
    'subItems': subItems.map((item) => item.toJson()).toList(),
  };

  factory LedgerTransaction.fromJson(Map<String, dynamic> json) =>
      LedgerTransaction(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        type: (json['type'] as String?) == TransactionType.payment.name
            ? TransactionType.payment
            : TransactionType.debt,
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        date:
            DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        method: json['method'] as String? ?? 'নগদ',
        subItems: ((json['subItems'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => DetailItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class DetailItem {
  const DetailItem({required this.name, required this.amount});

  final String name;
  final double amount;

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};

  factory DetailItem.fromJson(Map<String, dynamic> json) => DetailItem(
    name: json['name'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
  );
}

class _DetailItemDraft {
  _DetailItemDraft({String name = '', String amount = ''})
    : name = TextEditingController(text: name),
      amount = TextEditingController(text: amount);

  final TextEditingController name;
  final TextEditingController amount;

  DetailItem? toDetailItem() {
    final parsed = double.tryParse(amount.text.trim());
    if (name.text.trim().isEmpty || parsed == null || parsed <= 0) return null;
    return DetailItem(name: name.text.trim(), amount: parsed);
  }

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

double detailItemsTotal(List<DetailItem> items) {
  return items.fold<double>(0, (total, item) => total + item.amount);
}

String reminderMessageFor({
  required LedgerEntity entity,
  required double balance,
}) {
  final balanceText = taka(balance);
  final typeText = entity.type.isPositive ? 'পাওনা' : 'দেনা';
  final reminder = entity.reminderAt == null
      ? ''
      : '\nতারিখ: ${dateText(entity.reminderAt!)}';
  final note = entity.reminderNote.trim().isEmpty
      ? ''
      : '\nনোট: ${entity.reminderNote.trim()}';
  return 'আসসালামু আলাইকুম ${entity.name},\n'
      'দেনা পাওনা অ্যাপ অনুযায়ী আপনার $typeText হিসাব: $balanceText।'
      '$reminder$note\nধন্যবাদ।';
}

String normalizedPhoneForIntent(String phone) {
  return phone.replaceAll(RegExp(r'[^0-9+]'), '');
}

class ReminderNotificationService {
  ReminderNotificationService._();

  static final instance = ReminderNotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> scheduleEntityReminder(LedgerEntity entity) async {
    if (!_ready || entity.reminderAt == null || entity.reminderDone) return;
    final scheduleAt = entity.reminderAt!.isBefore(DateTime.now())
        ? DateTime.now().add(const Duration(minutes: 1))
        : entity.reminderAt!;
    await _plugin.zonedSchedule(
      id: entity.id.hashCode & 0x7fffffff,
      title: 'দেনা পাওনা রিমাইন্ডার',
      body: entity.reminderNote.isEmpty
          ? entity.name
          : '${entity.name}: ${entity.reminderNote}',
      scheduledDate: tz.TZDateTime.from(scheduleAt, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'denapaona_reminders',
          'দেনা পাওনা রিমাইন্ডার',
          channelDescription: 'Due date reminder alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelEntityReminder(String entityId) {
    if (!_ready) return Future<void>.value();
    return _plugin.cancel(id: entityId.hashCode & 0x7fffffff);
  }
}

class SyncOperation {
  SyncOperation({
    required this.id,
    required this.type,
    required this.collection,
    required this.documentId,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.status = SyncStatus.pending,
    this.attempts = 0,
    this.error,
  });

  final String id;
  final SyncOperationType type;
  final String collection;
  final String documentId;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;
  DateTime updatedAt;
  SyncStatus status;
  int attempts;
  String? error;

  bool get isDelete =>
      type == SyncOperationType.deleteEntity ||
      type == SyncOperationType.deleteTransaction;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'collection': collection,
    'documentId': documentId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'attempts': attempts,
    'error': error,
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
    id: json['id'] as String,
    type: SyncOperationType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => SyncOperationType.upsertEntity,
    ),
    collection: json['collection'] as String? ?? '',
    documentId: json['documentId'] as String? ?? '',
    payload: json['payload'] == null
        ? null
        : Map<String, dynamic>.from(json['payload'] as Map),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    status: SyncStatus.values.firstWhere(
      (status) => status.name == json['status'],
      orElse: () => SyncStatus.pending,
    ),
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    error: json['error'] as String?,
  );
}

List<LedgerEntity> resolveEntityConflicts({
  required List<LedgerEntity> local,
  required List<LedgerEntity> remote,
  required Set<String> pendingUpserts,
  required Set<String> pendingDeletes,
}) {
  final localById = {for (final entity in local) entity.id: entity};
  final remoteById = {for (final entity in remote) entity.id: entity};
  final resolved = <String, LedgerEntity>{};

  for (final entry in remoteById.entries) {
    final id = entry.key;
    if (pendingDeletes.contains(id)) continue;
    final localEntity = localById[id];
    if (localEntity == null) {
      resolved[id] = entry.value;
      continue;
    }
    resolved[id] =
        pendingUpserts.contains(id) ||
            localEntity.updatedAt.isAfter(entry.value.updatedAt)
        ? localEntity
        : entry.value;
  }

  for (final entry in localById.entries) {
    final id = entry.key;
    if (pendingDeletes.contains(id)) continue;
    if (pendingUpserts.contains(id)) {
      resolved[id] = entry.value;
    }
  }

  return resolved.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

List<LedgerTransaction> resolveTransactionConflicts({
  required List<LedgerTransaction> local,
  required List<LedgerTransaction> remote,
  required Set<String> pendingUpserts,
  required Set<String> pendingDeletes,
}) {
  final localById = {for (final tx in local) tx.id: tx};
  final remoteById = {for (final tx in remote) tx.id: tx};
  final resolved = <String, LedgerTransaction>{};

  for (final entry in remoteById.entries) {
    final id = entry.key;
    if (pendingDeletes.contains(id)) continue;
    final localTx = localById[id];
    if (localTx == null) {
      resolved[id] = entry.value;
      continue;
    }
    resolved[id] =
        pendingUpserts.contains(id) ||
            localTx.updatedAt.isAfter(entry.value.updatedAt)
        ? localTx
        : entry.value;
  }

  for (final entry in localById.entries) {
    final id = entry.key;
    if (pendingDeletes.contains(id)) continue;
    if (pendingUpserts.contains(id)) {
      resolved[id] = entry.value;
    }
  }

  return resolved.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

class LocalLedgerRepository {
  LocalLedgerRepository._(this._db) : _memory = false;
  LocalLedgerRepository._memory() : _db = null, _memory = true;

  static final _entityStore = sembast.stringMapStoreFactory.store('entities');
  static final _transactionStore = sembast.stringMapStoreFactory.store(
    'transactions',
  );
  static final _syncQueueStore = sembast.stringMapStoreFactory.store(
    'sync_queue',
  );
  static final _metaStore = sembast.stringMapStoreFactory.store('metadata');
  static const _themeModeKey = 'theme_mode_v1';
  static const _cloudSessionKey = 'cloud_session_v1';
  final sembast.Database? _db;
  final bool _memory;
  final Map<String, Map<String, dynamic>> _memoryEntities = {};
  final Map<String, Map<String, dynamic>> _memoryTransactions = {};
  final Map<String, Map<String, dynamic>> _memorySyncQueue = {};
  final Map<String, Map<String, dynamic>> _memoryMeta = {};

  static Future<LocalLedgerRepository> open() async {
    if (kIsWeb) {
      return LocalLedgerRepository._memory();
    }
    final directory = await getApplicationDocumentsDirectory();
    final database = await sembast.databaseFactoryIo.openDatabase(
      '${directory.path}/denapaona.db',
    );
    return LocalLedgerRepository._(database);
  }

  factory LocalLedgerRepository.fromDatabase(sembast.Database database) {
    return LocalLedgerRepository._(database);
  }

  Future<List<LedgerEntity>> loadEntities() async {
    if (_memory) {
      return _memoryEntities.values
          .map((value) => LedgerEntity.fromJson(value))
          .toList();
    }
    final records = await _entityStore.find(_db!);
    return records
        .map((record) => LedgerEntity.fromJson(record.value))
        .toList();
  }

  Future<List<LedgerTransaction>> loadTransactions() async {
    if (_memory) {
      return _memoryTransactions.values
          .map((value) => LedgerTransaction.fromJson(value))
          .toList();
    }
    final records = await _transactionStore.find(_db!);
    return records
        .map((record) => LedgerTransaction.fromJson(record.value))
        .toList();
  }

  Future<void> clearLedgerData() async {
    if (_memory) {
      _memoryEntities.clear();
      _memoryTransactions.clear();
      _memorySyncQueue.clear();
      return;
    }
    await _db!.transaction((txn) async {
      await _entityStore.delete(txn);
      await _transactionStore.delete(txn);
      await _syncQueueStore.delete(txn);
    });
  }

  Future<void> save(
    List<LedgerEntity> entities,
    List<LedgerTransaction> transactions,
  ) async {
    if (_memory) {
      _memoryEntities
        ..clear()
        ..addEntries(
          entities.map((entity) => MapEntry(entity.id, entity.toJson())),
        );
      _memoryTransactions
        ..clear()
        ..addEntries(transactions.map((tx) => MapEntry(tx.id, tx.toJson())));
      return;
    }
    await _db!.transaction((txn) async {
      await _entityStore.delete(txn);
      await _transactionStore.delete(txn);
      for (final entity in entities) {
        await _entityStore.record(entity.id).put(txn, entity.toJson());
      }
      for (final tx in transactions) {
        await _transactionStore.record(tx.id).put(txn, tx.toJson());
      }
    });
  }

  Future<void> enqueueOperation(SyncOperation operation) async {
    if (_memory) {
      _memorySyncQueue[operation.id] = operation.toJson();
      return;
    }
    await _syncQueueStore.record(operation.id).put(_db!, operation.toJson());
  }

  Future<void> enqueueOperations(List<SyncOperation> operations) async {
    if (_memory) {
      for (final operation in operations) {
        _memorySyncQueue[operation.id] = operation.toJson();
      }
      return;
    }
    await _db!.transaction((txn) async {
      for (final operation in operations) {
        await _syncQueueStore.record(operation.id).put(txn, operation.toJson());
      }
    });
  }

  Future<List<SyncOperation>> loadPendingOperations() async {
    if (_memory) {
      return _memorySyncQueue.values
          .where(
            (value) =>
                value['status'] == SyncStatus.pending.name ||
                value['status'] == SyncStatus.failed.name,
          )
          .map((value) => SyncOperation.fromJson(value))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final records = await _syncQueueStore.find(
      _db!,
      finder: sembast.Finder(
        filter: sembast.Filter.or([
          sembast.Filter.equals('status', SyncStatus.pending.name),
          sembast.Filter.equals('status', SyncStatus.failed.name),
        ]),
        sortOrders: [sembast.SortOrder('createdAt')],
      ),
    );
    return records
        .map((record) => SyncOperation.fromJson(record.value))
        .toList();
  }

  Future<int> pendingOperationCount() async {
    if (_memory) {
      return _memorySyncQueue.values
          .where(
            (value) =>
                value['status'] == SyncStatus.pending.name ||
                value['status'] == SyncStatus.failed.name,
          )
          .length;
    }
    return _syncQueueStore.count(
      _db!,
      filter: sembast.Filter.or([
        sembast.Filter.equals('status', SyncStatus.pending.name),
        sembast.Filter.equals('status', SyncStatus.failed.name),
      ]),
    );
  }

  Future<void> markOperationSynced(String id) async {
    if (_memory) {
      final operation = _memorySyncQueue[id];
      if (operation == null) return;
      _memorySyncQueue[id] = {
        ...operation,
        'status': SyncStatus.synced.name,
        'updatedAt': DateTime.now().toIso8601String(),
        'error': null,
      };
      return;
    }
    final operation = await _syncQueueStore.record(id).get(_db!);
    if (operation == null) return;
    await _syncQueueStore.record(id).put(_db, {
      ...operation,
      'status': SyncStatus.synced.name,
      'updatedAt': DateTime.now().toIso8601String(),
      'error': null,
    });
  }

  Future<void> markOperationFailed(String id, Object error) async {
    if (_memory) {
      final operation = _memorySyncQueue[id];
      if (operation == null) return;
      _memorySyncQueue[id] = {
        ...operation,
        'status': SyncStatus.failed.name,
        'attempts': ((operation['attempts'] as num?)?.toInt() ?? 0) + 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'error': error.toString(),
      };
      return;
    }
    final operation = await _syncQueueStore.record(id).get(_db!);
    if (operation == null) return;
    await _syncQueueStore.record(id).put(_db, {
      ...operation,
      'status': SyncStatus.failed.name,
      'attempts': ((operation['attempts'] as num?)?.toInt() ?? 0) + 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'error': error.toString(),
    });
  }

  Future<void> clearSyncedOperations() async {
    if (_memory) {
      _memorySyncQueue.removeWhere(
        (_, value) => value['status'] == SyncStatus.synced.name,
      );
      return;
    }
    await _syncQueueStore.delete(
      _db!,
      finder: sembast.Finder(
        filter: sembast.Filter.equals('status', SyncStatus.synced.name),
      ),
    );
  }

  String exportJson(
    List<LedgerEntity> entities,
    List<LedgerTransaction> transactions,
  ) {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'দেনা পাওনা',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'entities': entities.map((entity) => entity.toJson()).toList(),
      'transactions': transactions.map((tx) => tx.toJson()).toList(),
    });
  }

  Future<(List<LedgerEntity>, List<LedgerTransaction>)> importJson(
    String raw,
  ) async {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entities = ((decoded['entities'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => LedgerEntity.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final transactions = ((decoded['transactions'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) => LedgerTransaction.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    await save(entities, transactions);
    return (entities, transactions);
  }

  Future<ThemeMode> getThemeMode() async {
    if (_memory) {
      final mode = _memoryMeta[_themeModeKey]?['mode'] as String?;
      return ThemeMode.values.firstWhere(
        (item) => item.name == mode,
        orElse: () => ThemeMode.light,
      );
    }
    final value = await _metaStore.record(_themeModeKey).get(_db!);
    final mode = value?['mode'] as String?;
    return ThemeMode.values.firstWhere(
      (item) => item.name == mode,
      orElse: () => ThemeMode.light,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_memory) {
      _memoryMeta[_themeModeKey] = {'mode': mode.name};
      return;
    }
    await _metaStore.record(_themeModeKey).put(_db!, {'mode': mode.name});
  }

  Future<({String? projectId, String? uid})> getCloudSession() async {
    if (_memory) {
      final value = _memoryMeta[_cloudSessionKey];
      return (
        projectId: value?['projectId'] as String?,
        uid: value?['uid'] as String?,
      );
    }
    final value = await _metaStore.record(_cloudSessionKey).get(_db!);
    return (
      projectId: value?['projectId'] as String?,
      uid: value?['uid'] as String?,
    );
  }

  Future<void> setCloudSession({
    required String projectId,
    required String uid,
  }) async {
    if (_memory) {
      _memoryMeta[_cloudSessionKey] = {'projectId': projectId, 'uid': uid};
      return;
    }
    await _metaStore.record(_cloudSessionKey).put(_db!, {
      'projectId': projectId,
      'uid': uid,
    });
  }

  Future<void> close() {
    if (_memory) return Future<void>.value();
    return _db!.close();
  }
}

class LedgerController extends ChangeNotifier {
  LedgerController({required this.firebaseReady, this.repositoryFactory});

  final bool firebaseReady;
  final Future<LocalLedgerRepository> Function()? repositoryFactory;
  LocalLedgerRepository? _local;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _entitySyncSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _transactionSyncSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _snapshotSyncSub;
  StreamSubscription<User?>? _authSub;

  bool loading = true;
  bool signedIn = false;
  bool cloudConnected = false;
  String? authError;
  String? firestoreError;
  bool syncInProgress = false;
  bool _applyingRemoteChanges = false;
  bool _initialSnapshotHandled = false;
  int pendingSyncCount = 0;
  String? userEmail;
  String search = '';
  ThemeMode themeMode = ThemeMode.light;
  List<LedgerEntity> entities = [];
  List<LedgerTransaction> transactions = [];
  bool _ledgerIndexesDirty = true;
  Map<String, List<LedgerTransaction>> _transactionsByEntity = {};
  Map<String, double> _entityTotals = {};
  Map<LedgerType, double> _typeTotals = {};

  void _markLedgerIndexesDirty() {
    _ledgerIndexesDirty = true;
  }

  void _ensureLedgerIndexes() {
    if (!_ledgerIndexesDirty) return;

    final byEntity = <String, List<LedgerTransaction>>{};
    final entityTotals = <String, double>{};
    for (final tx in transactions) {
      byEntity.putIfAbsent(tx.entityId, () => <LedgerTransaction>[]).add(tx);
      final signedAmount = tx.type == TransactionType.debt
          ? tx.amount
          : -tx.amount;
      entityTotals[tx.entityId] =
          (entityTotals[tx.entityId] ?? 0) + signedAmount;
    }
    for (final list in byEntity.values) {
      list.sort((a, b) => b.date.compareTo(a.date));
    }

    final typeTotals = {for (final type in LedgerType.values) type: 0.0};
    for (final entity in entities) {
      typeTotals[entity.type] =
          (typeTotals[entity.type] ?? 0) + (entityTotals[entity.id] ?? 0);
    }

    _transactionsByEntity = byEntity;
    _entityTotals = entityTotals;
    _typeTotals = typeTotals;
    _ledgerIndexesDirty = false;
  }

  Future<void> boot() async {
    _local = repositoryFactory == null
        ? await LocalLedgerRepository.open()
        : await repositoryFactory!();
    themeMode = await _local!.getThemeMode();
    await _refreshPendingSyncCount();

    if (firebaseReady) {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        await _prepareCloudSession(current.uid);
        entities = await _local!.loadEntities();
        transactions = await _local!.loadTransactions();
        _markLedgerIndexesDirty();
        signedIn = true;
        userEmail = current.email;
        _listenToFirestore(current.uid);
        unawaited(flushSyncQueue());
      }
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        debugPrint(
          'Firebase auth state: ${user == null ? 'signedOut' : 'signedIn uid=${user.uid} email=${user.email}'}',
        );
      });
    } else {
      authError =
          'Firebase চালু হয়নি। google-services.json ও ইন্টারনেট সংযোগ যাচাই করুন।';
      debugPrint(
        'Firebase Auth disabled because Firebase initialization failed.',
      );
    }

    loading = false;
    notifyListeners();
  }

  bool get isDarkMode => themeMode == ThemeMode.dark;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    await _local?.setThemeMode(mode);
  }

  Future<void> toggleTheme() async {
    await setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  String get _firebaseProjectId =>
      Firebase.apps.isEmpty ? 'unknown' : Firebase.app().options.projectId;

  Future<void> _prepareCloudSession(String uid) async {
    final projectId = _firebaseProjectId;
    final session = await _local?.getCloudSession();
    if (session?.projectId != projectId || session?.uid != uid) {
      debugPrint(
        'Cloud session changed: oldProject=${session?.projectId}, newProject=$projectId, oldUid=${session?.uid}, newUid=$uid. Clearing local ledger cache.',
      );
      await _local?.clearLedgerData();
      await _refreshPendingSyncCount();
    }
    await _local?.setCloudSession(projectId: projectId, uid: uid);
  }

  Future<void> signIn(String email, String password, bool signUp) async {
    if (email.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('ইমেইল ও পাসওয়ার্ড দিন');
    }

    if (!firebaseReady) {
      throw Exception(authError ?? 'Firebase সংযোগ পাওয়া যায়নি');
    }

    final auth = FirebaseAuth.instance;
    debugPrint(
      'Firebase Auth email ${signUp ? 'signup' : 'signin'} requested for ${email.trim()}',
    );
    final credential = signUp
        ? await auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
        : await auth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
    await _activateFirebaseUser(credential.user, fallbackEmail: email.trim());
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    if (!firebaseReady) {
      throw Exception(authError ?? 'Firebase সংযোগ পাওয়া যায়নি');
    }
    debugPrint('Firebase Auth Google sign-in requested');
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final result = await FirebaseAuth.instance.signInWithPopup(provider);
      await _activateFirebaseUser(result.user);
      notifyListeners();
      return;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    await _activateFirebaseUser(result.user, fallbackEmail: account.email);
    notifyListeners();
  }

  Future<void> _activateFirebaseUser(
    User? user, {
    String? fallbackEmail,
  }) async {
    if (user == null) throw Exception('Firebase user পাওয়া যায়নি');
    await _prepareCloudSession(user.uid);
    entities = await _local?.loadEntities() ?? [];
    transactions = await _local?.loadTransactions() ?? [];
    _markLedgerIndexesDirty();
    signedIn = true;
    authError = null;
    userEmail = user.email ?? fallbackEmail;
    debugPrint(
      'Firebase Auth active: project=$_firebaseProjectId uid=${user.uid} email=$userEmail',
    );
    _listenToFirestore(user.uid);
    unawaited(flushSyncQueue());
  }

  Future<void> signOut() async {
    if (firebaseReady) await FirebaseAuth.instance.signOut();
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _entitySyncSub?.cancel();
    await _transactionSyncSub?.cancel();
    await _snapshotSyncSub?.cancel();
    signedIn = false;
    userEmail = null;
    cloudConnected = false;
    syncInProgress = false;
    entities = [];
    transactions = [];
    _markLedgerIndexesDirty();
    debugPrint('Firebase Auth signed out');
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  void _listenToFirestore(String uid) {
    cloudConnected = true;
    final root = FirebaseFirestore.instance.collection('users').doc(uid);
    firestoreError = null;
    debugPrint(
      'Firestore listening: users/$uid in project $_firebaseProjectId',
    );
    _initialSnapshotHandled = false;

    _entitySyncSub?.cancel();
    _transactionSyncSub?.cancel();
    _snapshotSyncSub?.cancel();

    _entitySyncSub = root
        .collection('entities')
        .snapshots()
        .listen(
          (snapshot) => _applyRemoteEntities(uid, snapshot),
          onError: (error) {
            firestoreError = error.toString();
            debugPrint('Firestore entities listener error: $error');
            cloudConnected = false;
            notifyListeners();
          },
        );
    _transactionSyncSub = root
        .collection('transactions')
        .snapshots()
        .listen(
          (snapshot) => _applyRemoteTransactions(uid, snapshot),
          onError: (error) {
            firestoreError = error.toString();
            debugPrint('Firestore transactions listener error: $error');
            cloudConnected = false;
            notifyListeners();
          },
        );
    _snapshotSyncSub = root
        .collection('snapshots')
        .doc('latest')
        .snapshots()
        .listen(
          _applyRemoteSnapshot,
          onError: (error) {
            firestoreError = error.toString();
            debugPrint('Firestore snapshot listener error: $error');
            cloudConnected = false;
            notifyListeners();
          },
        );
  }

  Future<void> _applyRemoteEntities(
    String uid,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.metadata.hasPendingWrites || syncInProgress) return;

    final pending = await _pendingIntentFor('entities');
    debugPrint(
      'Firestore read: users/$uid/entities count=${snapshot.docs.length}',
    );
    final remoteEntities = snapshot.docs
        .map((doc) => LedgerEntity.fromJson(doc.data()))
        .toList();
    _applyingRemoteChanges = true;
    entities = resolveEntityConflicts(
      local: entities,
      remote: remoteEntities,
      pendingUpserts: pending.upserts,
      pendingDeletes: pending.deletes,
    );
    _markLedgerIndexesDirty();
    await _local?.save(entities, transactions);
    _applyingRemoteChanges = false;
    cloudConnected = true;
    notifyListeners();
  }

  Future<void> _applyRemoteTransactions(
    String uid,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.metadata.hasPendingWrites || syncInProgress) return;

    final pending = await _pendingIntentFor('transactions');
    debugPrint(
      'Firestore read: users/$uid/transactions count=${snapshot.docs.length}',
    );
    final remoteTransactions = snapshot.docs
        .map((doc) => LedgerTransaction.fromJson(doc.data()))
        .toList();
    _applyingRemoteChanges = true;
    transactions = resolveTransactionConflicts(
      local: transactions,
      remote: remoteTransactions,
      pendingUpserts: pending.upserts,
      pendingDeletes: pending.deletes,
    );
    _markLedgerIndexesDirty();
    await _local?.save(entities, transactions);
    _applyingRemoteChanges = false;
    cloudConnected = true;
    notifyListeners();
  }

  Future<void> _applyRemoteSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!_initialSnapshotHandled) {
      _initialSnapshotHandled = true;
      if (!snapshot.exists) return;
    }
    if (!snapshot.exists ||
        snapshot.metadata.hasPendingWrites ||
        syncInProgress) {
      return;
    }
    final data = snapshot.data();
    if (data == null) return;
    final remoteEntities = ((data['entities'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => LedgerEntity.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final remoteTransactions = ((data['transactions'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) => LedgerTransaction.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    if (remoteEntities.isEmpty && remoteTransactions.isEmpty) return;

    final pendingEntities = await _pendingIntentFor('entities');
    final pendingTransactions = await _pendingIntentFor('transactions');
    _applyingRemoteChanges = true;
    entities = resolveEntityConflicts(
      local: entities,
      remote: remoteEntities,
      pendingUpserts: pendingEntities.upserts,
      pendingDeletes: pendingEntities.deletes,
    );
    transactions = resolveTransactionConflicts(
      local: transactions,
      remote: remoteTransactions,
      pendingUpserts: pendingTransactions.upserts,
      pendingDeletes: pendingTransactions.deletes,
    );
    _markLedgerIndexesDirty();
    await _local?.save(entities, transactions);
    _applyingRemoteChanges = false;
    cloudConnected = true;
    notifyListeners();
  }

  Future<void> _persist([SyncOperation? operation]) async {
    await _local?.save(entities, transactions);
    if (_applyingRemoteChanges) return;
    if (operation != null) {
      debugPrint(
        'Local sync queued: ${operation.type.name} ${operation.collection}/${operation.documentId}',
      );
      await _local?.enqueueOperation(operation);
      await _refreshPendingSyncCount();
    }
    if (firebaseReady && FirebaseAuth.instance.currentUser != null) {
      await flushSyncQueue();
    }
  }

  Future<void> _refreshPendingSyncCount() async {
    pendingSyncCount = await _local?.pendingOperationCount() ?? 0;
  }

  Future<({Set<String> upserts, Set<String> deletes})> _pendingIntentFor(
    String collection,
  ) async {
    final operations = await _local?.loadPendingOperations() ?? const [];
    final upserts = <String>{};
    final deletes = <String>{};
    for (final operation in operations) {
      if (operation.collection != collection) continue;
      if (operation.isDelete) {
        deletes.add(operation.documentId);
      } else {
        upserts.add(operation.documentId);
      }
    }
    return (upserts: upserts, deletes: deletes);
  }

  Future<void> flushSyncQueue() async {
    if (syncInProgress ||
        !firebaseReady ||
        FirebaseAuth.instance.currentUser == null ||
        _local == null) {
      cloudConnected = false;
      await _refreshPendingSyncCount();
      notifyListeners();
      return;
    }
    syncInProgress = true;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final root = FirebaseFirestore.instance.collection('users').doc(uid);
    final operations = await _local!.loadPendingOperations();
    debugPrint(
      'Firestore sync start: project=$_firebaseProjectId uid=$uid pending=${operations.length}',
    );

    for (final operation in operations) {
      try {
        final document = root
            .collection(operation.collection)
            .doc(operation.documentId);
        debugPrint(
          'Firestore write: users/$uid/${operation.collection}/${operation.documentId} ${operation.type.name}',
        );
        if (operation.isDelete) {
          await document.delete();
        } else {
          await document.set(operation.payload ?? <String, dynamic>{});
        }
        await _local!.markOperationSynced(operation.id);
      } catch (error) {
        await _local!.markOperationFailed(operation.id, error);
      }
    }

    await _local!.clearSyncedOperations();
    await _refreshPendingSyncCount();
    syncInProgress = false;
    cloudConnected = pendingSyncCount == 0;
    notifyListeners();
  }

  SyncOperation _operation({
    required SyncOperationType type,
    required String collection,
    required String documentId,
    Map<String, dynamic>? payload,
  }) {
    final now = DateTime.now();
    return SyncOperation(
      id: 'sync_${now.microsecondsSinceEpoch}_${type.name}_$documentId',
      type: type,
      collection: collection,
      documentId: documentId,
      payload: payload,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<LedgerEntity> byType(LedgerType type) {
    final query = search.trim().toLowerCase();
    return entities.where((entity) {
      final matchesType = entity.type == type;
      final matchesSearch =
          query.isEmpty ||
          entity.name.toLowerCase().contains(query) ||
          entity.phone.toLowerCase().contains(query);
      return matchesType && matchesSearch;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<LedgerTransaction> transactionsFor(String entityId) {
    _ensureLedgerIndexes();
    return List<LedgerTransaction>.unmodifiable(
      _transactionsByEntity[entityId] ?? const <LedgerTransaction>[],
    );
  }

  double entityTotal(String entityId) {
    _ensureLedgerIndexes();
    return _entityTotals[entityId] ?? 0;
  }

  double typeTotal(LedgerType type) {
    _ensureLedgerIndexes();
    return _typeTotals[type] ?? 0;
  }

  double get allDebt =>
      typeTotal(LedgerType.shopDebt) + typeTotal(LedgerType.generalDebt);

  double get receivable => typeTotal(LedgerType.receivable);

  double get amanot => typeTotal(LedgerType.amanot);

  Map<LedgerType, double> get moduleTotals {
    _ensureLedgerIndexes();
    return Map<LedgerType, double>.unmodifiable(_typeTotals);
  }

  Map<String, double> monthlyTransactionTotals({int months = 6}) {
    final formatter = DateFormat('MMM yy');
    final now = DateTime.now();
    final result = <String, double>{};
    for (var i = months - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i);
      result[formatter.format(date)] = 0;
    }
    for (final tx in transactions) {
      final key = formatter.format(DateTime(tx.date.year, tx.date.month));
      if (result.containsKey(key)) {
        result[key] = (result[key] ?? 0) + tx.amount;
      }
    }
    return result;
  }

  List<LedgerEntity> topEntities({int limit = 5}) {
    _ensureLedgerIndexes();
    final sorted = [...entities]
      ..sort(
        (a, b) =>
            (_entityTotals[b.id] ?? 0).compareTo(_entityTotals[a.id] ?? 0),
      );
    return sorted.take(limit).toList();
  }

  List<LedgerEntity> get activeReminders {
    final reminders =
        entities
            .where(
              (entity) => entity.reminderAt != null && !entity.reminderDone,
            )
            .toList()
          ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    return reminders;
  }

  List<LedgerEntity> get overdueReminders {
    final now = DateTime.now();
    return activeReminders
        .where((entity) => entity.reminderAt!.isBefore(now))
        .toList();
  }

  Future<void> addEntity(
    LedgerType type,
    String name,
    String phone, {
    String fatherName = '',
    String address = '',
  }) async {
    final now = DateTime.now();
    final entity = LedgerEntity(
      id: 'entity_${now.microsecondsSinceEpoch}',
      type: type,
      name: name.trim(),
      fatherName: fatherName.trim(),
      address: address.trim(),
      phone: phone.trim(),
      createdAt: now,
      updatedAt: now,
    );
    entities.add(entity);
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.upsertEntity,
        collection: 'entities',
        documentId: entity.id,
        payload: entity.toJson(),
      ),
    );
    notifyListeners();
  }

  Future<void> updateEntity(
    LedgerEntity entity,
    String name,
    String phone, {
    String? fatherName,
    String? address,
  }) async {
    entity.name = name.trim();
    entity.fatherName = (fatherName ?? entity.fatherName).trim();
    entity.address = (address ?? entity.address).trim();
    entity.phone = phone.trim();
    entity.updatedAt = DateTime.now();
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.upsertEntity,
        collection: 'entities',
        documentId: entity.id,
        payload: entity.toJson(),
      ),
    );
    notifyListeners();
  }

  Future<void> updateReminder(
    LedgerEntity entity, {
    DateTime? reminderAt,
    String reminderNote = '',
    bool reminderDone = false,
  }) async {
    entity.reminderAt = reminderAt;
    entity.reminderNote = reminderNote.trim();
    entity.reminderDone = reminderDone;
    entity.updatedAt = DateTime.now();
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.upsertEntity,
        collection: 'entities',
        documentId: entity.id,
        payload: entity.toJson(),
      ),
    );
    notifyListeners();
  }

  Future<void> completeReminder(LedgerEntity entity) async {
    await updateReminder(
      entity,
      reminderAt: entity.reminderAt,
      reminderNote: entity.reminderNote,
      reminderDone: true,
    );
  }

  String reminderMessage(LedgerEntity entity) {
    return reminderMessageFor(entity: entity, balance: entityTotal(entity.id));
  }

  Future<void> deleteEntity(String entityId) async {
    entities.removeWhere((entity) => entity.id == entityId);
    final deletedTransactions = transactions
        .where((tx) => tx.entityId == entityId)
        .map((tx) => tx.id)
        .toList();
    transactions.removeWhere((tx) => tx.entityId == entityId);
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.deleteEntity,
        collection: 'entities',
        documentId: entityId,
      ),
    );
    for (final txId in deletedTransactions) {
      await _local?.enqueueOperation(
        _operation(
          type: SyncOperationType.deleteTransaction,
          collection: 'transactions',
          documentId: txId,
        ),
      );
    }
    await _refreshPendingSyncCount();
    unawaited(flushSyncQueue());
    notifyListeners();
  }

  Future<void> addTransaction({
    required String entityId,
    required TransactionType type,
    required String description,
    required double amount,
    required DateTime date,
    String method = 'নগদ',
    List<DetailItem> subItems = const [],
  }) async {
    final now = DateTime.now();
    final transaction = LedgerTransaction(
      id: 'tx_${now.microsecondsSinceEpoch}',
      entityId: entityId,
      type: type,
      description: description.trim(),
      amount: amount,
      date: date,
      updatedAt: now,
      method: method,
      subItems: subItems,
    );
    transactions.add(transaction);
    final entity = entities.firstWhere((item) => item.id == entityId);
    entity.updatedAt = now;
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.upsertTransaction,
        collection: 'transactions',
        documentId: transaction.id,
        payload: transaction.toJson(),
      ),
    );
    notifyListeners();
  }

  Future<void> updateTransaction({
    required String id,
    required TransactionType type,
    required String description,
    required double amount,
    required DateTime date,
    required String method,
    List<DetailItem> subItems = const [],
  }) async {
    final index = transactions.indexWhere((tx) => tx.id == id);
    if (index == -1) return;
    final previous = transactions[index];
    final now = DateTime.now();
    final updated = LedgerTransaction(
      id: previous.id,
      entityId: previous.entityId,
      type: type,
      description: description.trim(),
      amount: amount,
      date: date,
      updatedAt: now,
      method: method,
      subItems: subItems,
    );
    transactions[index] = updated;
    final entity = entities
        .where((item) => item.id == previous.entityId)
        .firstOrNull;
    if (entity != null) entity.updatedAt = now;
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.upsertTransaction,
        collection: 'transactions',
        documentId: updated.id,
        payload: updated.toJson(),
      ),
    );
    notifyListeners();
  }

  Future<void> deleteTransaction(String id) async {
    final deleted = transactions.where((tx) => tx.id == id).firstOrNull;
    transactions.removeWhere((tx) => tx.id == id);
    if (deleted != null) {
      final entity = entities
          .where((item) => item.id == deleted.entityId)
          .firstOrNull;
      if (entity != null) entity.updatedAt = DateTime.now();
    }
    _markLedgerIndexesDirty();
    await _persist(
      _operation(
        type: SyncOperationType.deleteTransaction,
        collection: 'transactions',
        documentId: id,
      ),
    );
    notifyListeners();
  }

  String exportJson() => _local!.exportJson(entities, transactions);

  Future<File> exportJsonFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory('${directory.path}/backups');
    if (!await backupDirectory.exists()) {
      await backupDirectory.create(recursive: true);
    }
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${backupDirectory.path}/dena_paona_$timestamp.json');
    return file.writeAsString(exportJson(), encoding: utf8);
  }

  Future<void> importJson(String raw) async {
    final result = await _local!.importJson(raw);
    entities = result.$1;
    transactions = result.$2;
    _markLedgerIndexesDirty();
    final snapshotOperation = _operation(
      type: SyncOperationType.importSnapshot,
      collection: 'snapshots',
      documentId: 'latest',
      payload: {
        'entities': entities.map((entity) => entity.toJson()).toList(),
        'transactions': transactions.map((tx) => tx.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    final entityOperations = entities.map(
      (entity) => _operation(
        type: SyncOperationType.upsertEntity,
        collection: 'entities',
        documentId: entity.id,
        payload: entity.toJson(),
      ),
    );
    final transactionOperations = transactions.map(
      (tx) => _operation(
        type: SyncOperationType.upsertTransaction,
        collection: 'transactions',
        documentId: tx.id,
        payload: tx.toJson(),
      ),
    );
    await _local?.enqueueOperations([
      snapshotOperation,
      ...entityOperations,
      ...transactionOperations,
    ]);
    await _refreshPendingSyncCount();
    if (firebaseReady && FirebaseAuth.instance.currentUser != null) {
      await flushSyncQueue();
    }
    notifyListeners();
  }

  Future<void> importJsonFile(File file) async {
    final raw = await file.readAsString(encoding: utf8);
    await importJson(raw);
  }

  Future<void> syncNow() async {
    await flushSyncQueue();
  }

  @override
  void dispose() {
    _entitySyncSub?.cancel();
    _transactionSyncSub?.cancel();
    _snapshotSyncSub?.cancel();
    _authSub?.cancel();
    unawaited(_local?.close());
    super.dispose();
  }
}

class DenaPaonaApp extends StatelessWidget {
  const DenaPaonaApp({
    super.key,
    required this.firebaseReady,
    this.repositoryFactory,
  });

  final bool firebaseReady;
  final Future<LocalLedgerRepository> Function()? repositoryFactory;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LedgerController(
        firebaseReady: firebaseReady,
        repositoryFactory: repositoryFactory,
      )..boot(),
      child: Consumer<LedgerController>(
        builder: (context, controller, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'দেনা পাওনা',
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: controller.themeMode,
          home: const AppGate(),
        ),
      ),
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF111827) : AppColors.surface;
  final surfaceHigh = isDark ? const Color(0xFF1F2937) : AppColors.surfaceHigh;
  final onSurface = isDark ? const Color(0xFFEAF2F1) : AppColors.text;

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'TiroBangla',
    brightness: brightness,
    scaffoldBackgroundColor: surface,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: AppColors.primary,
      primary: isDark ? AppColors.accent : AppColors.primary,
      secondary: AppColors.accent,
      surface: surface,
      onSurface: onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: isDark ? AppColors.accent : AppColors.primary,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: isDark ? AppColors.accent : AppColors.primary,
        fontFamily: 'TiroBangla',
        fontWeight: FontWeight.w800,
        fontSize: 26,
      ),
      iconTheme: IconThemeData(
        color: isDark ? AppColors.accent : AppColors.primary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.accent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: onSurface,
          fontFamily: 'TiroBangla',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF182333) : AppColors.white,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: (isDark ? AppColors.accent : AppColors.primary).withValues(
            alpha: .28,
          ),
          width: 2,
        ),
      ),
      labelStyle: TextStyle(color: onSurface.withValues(alpha: .72)),
      hintStyle: TextStyle(color: onSurface.withValues(alpha: .56)),
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
      fontFamily: 'TiroBangla',
    ),
    dividerColor: onSurface.withValues(alpha: .10),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? const Color(0xFF243447) : AppColors.primary,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'TiroBangla',
      ),
    ),
  );
}

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return controller.signedIn ? const HomeShell() : const LoginScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: softDecoration(AppColors.white, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: softShadow,
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'দেনা পাওনা',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.firebaseReady
                          ? 'Firebase ক্লাউডে নিরাপদ সিঙ্ক'
                          : controller.authError ??
                                'Firebase সংযোগ পাওয়া যায়নি',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'ইমেইল ঠিকানা',
                        suffixIcon: Icon(Icons.mail_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'পাসওয়ার্ড',
                        suffixIcon: Icon(Icons.lock_rounded),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(_signUp ? 'অ্যাকাউন্ট খুলুন' : 'লগইন করুন'),
                      style: primaryButtonStyle(),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy || !controller.firebaseReady
                          ? null
                          : _submitGoogle,
                      icon: const Icon(Icons.account_circle_rounded),
                      label: const Text('Google দিয়ে লগইন'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _signUp = !_signUp),
                      child: Text(
                        _signUp
                            ? 'আগেই অ্যাকাউন্ট আছে? লগইন করুন'
                            : 'অ্যাকাউন্ট নেই? নতুন অ্যাকাউন্ট খুলুন',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await context.read<LedgerController>().signIn(
        _email.text,
        _password.text,
        _signUp,
      );
    } catch (error) {
      if (mounted) {
        showSnack(context, error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _busy = true);
    try {
      await context.read<LedgerController>().signInWithGoogle();
    } catch (error) {
      if (mounted) {
        showSnack(context, error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final colors = Theme.of(context).colorScheme;
    final tabs = [
      const DashboardScreen(),
      const LedgerListScreen(type: LedgerType.shopDebt),
      const LedgerListScreen(type: LedgerType.generalDebt),
      const LedgerListScreen(type: LedgerType.receivable),
      const LedgerListScreen(type: LedgerType.amanot),
      const ReportsScreen(),
      const DataScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
          return;
        }
        final exit = await confirmDialog(context, 'অ্যাপ বন্ধ করবেন?');
        if (exit && context.mounted) {
          await SystemNavigator.pop(animated: true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.surface.withValues(alpha: .88),
          elevation: 0,
          title: Text(
            'দেনা পাওনা',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 26,
            ),
          ),
          actions: [
            IconButton(
              tooltip: controller.isDarkMode ? 'লাইট মোড' : 'ডার্ক মোড',
              onPressed: controller.toggleTheme,
              icon: Icon(
                controller.isDarkMode
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: colors.primary,
              ),
            ),
            IconButton(
              tooltip: 'সাইন আউট',
              onPressed: () => context.read<LedgerController>().signOut(),
              icon: Icon(Icons.logout_rounded, color: colors.primary),
            ),
          ],
        ),
        body: tabs[_index],
        floatingActionButton: _index == 0 || _index >= 5
            ? FloatingActionButton.extended(
                onPressed: () => setState(() => _index = 1),
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.primary,
                icon: const Icon(Icons.add_rounded),
                label: const Text('নতুন এন্ট্রি'),
              )
            : FloatingActionButton(
                onPressed: () => showEntitySheet(context, tabType(_index)),
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.primary,
                child: const Icon(Icons.add_rounded),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          backgroundColor: colors.surface.withValues(alpha: .96),
          indicatorColor: AppColors.accent,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_rounded),
              label: 'ড্যাশবোর্ড',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_rounded),
              label: 'দোকান',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_search_rounded),
              label: 'দেনা',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_rounded),
              label: 'পাওনা',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_rounded),
              label: 'আমানত',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_rounded),
              label: 'রিপোর্ট',
            ),
            NavigationDestination(
              icon: Icon(Icons.storage_rounded),
              label: 'ডাটা',
            ),
          ],
        ),
      ),
    );
  }

  LedgerType tabType(int index) => switch (index) {
    1 => LedgerType.shopDebt,
    2 => LedgerType.generalDebt,
    3 => LedgerType.receivable,
    4 => LedgerType.amanot,
    _ => LedgerType.shopDebt,
  };
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final recent = controller.transactions.take(4).toList();
    return RefreshIndicator(
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (context.mounted) showSnack(context, 'ডাটা রিফ্রেশ হয়েছে');
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'সর্বমোট দেনা',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  taka(controller.allDebt),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () =>
                      showEntitySheet(context, LedgerType.shopDebt),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('নতুন এন্ট্রি'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SummaryTile(type: LedgerType.shopDebt),
              SummaryTile(type: LedgerType.generalDebt),
              SummaryTile(type: LedgerType.receivable),
              SummaryTile(type: LedgerType.amanot),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'সাম্প্রতিক লেনদেন',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              StatusChip(
                label: controller.pendingSyncCount > 0
                    ? 'Pending ${controller.pendingSyncCount}'
                    : controller.cloudConnected
                    ? 'Cloud Sync'
                    : 'Offline',
                icon: controller.pendingSyncCount > 0
                    ? Icons.sync_rounded
                    : controller.cloudConnected
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                onTap: controller.pendingSyncCount > 0
                    ? controller.flushSyncQueue
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.activeReminders.isNotEmpty) ...[
            ReportSection(
              title: 'রিমাইন্ডার',
              child: Column(
                children: controller.activeReminders.take(3).map((entity) {
                  final overdue = entity.reminderAt!.isBefore(DateTime.now());
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconBadge(
                      icon: overdue
                          ? Icons.notification_important_rounded
                          : Icons.notifications_active_rounded,
                      color: overdue ? AppColors.error : AppColors.primary,
                    ),
                    title: Text(
                      entity.name,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      entity.reminderNote.isEmpty
                          ? dateText(entity.reminderAt!)
                          : '${entity.reminderNote} • ${dateText(entity.reminderAt!)}',
                    ),
                    trailing: TextButton(
                      onPressed: () => context
                          .read<LedgerController>()
                          .completeReminder(entity),
                      child: const Text('Done'),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          ...recent.map((tx) => TransactionCard(transaction: tx)),
        ],
      ),
    );
  }
}

class SummaryTile extends StatelessWidget {
  const SummaryTile({super.key, required this.type});

  final LedgerType type;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final color = type.isPositive ? AppColors.success : AppColors.error;
    return SizedBox(
      width: MediaQuery.sizeOf(context).width > 650
          ? (MediaQuery.sizeOf(context).width - 70) / 2
          : double.infinity,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: softDecoration(AppColors.surfaceLow, 24),
        child: Row(
          children: [
            IconBadge(icon: type.icon, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.totalTitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    taka(controller.typeTotal(type)),
                    style: TextStyle(
                      color: color,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LedgerListScreen extends StatelessWidget {
  const LedgerListScreen({super.key, required this.type});

  final LedgerType type;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final items = controller.byType(type);
    return RefreshIndicator(
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (context.mounted) showSnack(context, 'তালিকা আপডেট হয়েছে');
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
        children: [
          HeroTotalCard(type: type),
          const SizedBox(height: 18),
          TextField(
            onChanged: context.read<LedgerController>().setSearch,
            decoration: const InputDecoration(
              hintText: 'নাম অথবা ফোন নম্বর দিয়ে খুঁজুন',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            EmptyState(
              icon: type.icon,
              title: 'এখনও কোনো হিসাব নেই',
              subtitle: '${type.title} হিসাব যোগ করতে + চাপুন',
            )
          else
            ...items.map((entity) => LedgerEntityCard(entity: entity)),
        ],
      ),
    );
  }
}

class HeroTotalCard extends StatelessWidget {
  const HeroTotalCard({super.key, required this.type});

  final LedgerType type;

  @override
  Widget build(BuildContext context) {
    final total = context.watch<LedgerController>().typeTotal(type);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.totalTitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  taka(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Icon(type.icon, color: AppColors.accent, size: 44),
        ],
      ),
    );
  }
}

String displayOrDash(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '-' : trimmed;
}

class EntityIdentityDetails extends StatelessWidget {
  const EntityIdentityDetails({
    super.key,
    required this.entity,
    this.labelColor = AppColors.muted,
    this.valueColor = AppColors.primary,
  });

  final LedgerEntity entity;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EntityInfoLine(
          label: 'নাম',
          value: displayOrDash(entity.name),
          labelColor: labelColor,
          valueColor: valueColor,
          isPrimary: true,
        ),
        const SizedBox(height: 4),
        _EntityInfoLine(
          label: 'পিতার নাম',
          value: displayOrDash(entity.fatherName),
          labelColor: labelColor,
          valueColor: valueColor,
        ),
        const SizedBox(height: 4),
        _EntityInfoLine(
          label: 'ঠিকানা',
          value: displayOrDash(entity.address),
          labelColor: labelColor,
          valueColor: valueColor,
        ),
        const SizedBox(height: 4),
        _EntityInfoLine(
          label: 'নাম্বার',
          value: displayOrDash(entity.phone),
          labelColor: labelColor,
          valueColor: valueColor,
        ),
      ],
    );
  }
}

class _EntityInfoLine extends StatelessWidget {
  const _EntityInfoLine({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    this.isPrimary = false,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: labelColor, fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor,
              fontWeight: isPrimary ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
      maxLines: isPrimary ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: TextStyle(fontSize: isPrimary ? 18 : 13, height: 1.25),
    );
  }
}

class LedgerEntityCard extends StatelessWidget {
  const LedgerEntityCard({super.key, required this.entity});

  final LedgerEntity entity;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final total = controller.entityTotal(entity.id);
    final color = entity.type.isPositive ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetailsScreen(entityId: entity.id)),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: softDecoration(AppColors.surfaceLow, 24),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          taka(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'বকেয়া / ব্যালেন্স',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: EntityIdentityDetails(entity: entity)),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: IconButtonTheme(
                  data: IconButtonThemeData(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(34, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'এডিট',
                        onPressed: () => showEntitySheet(
                          context,
                          entity.type,
                          entity: entity,
                        ),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: 'SMS',
                        onPressed: () => sendReminderSms(context, entity),
                        icon: const Icon(Icons.sms_rounded),
                      ),
                      IconButton(
                        tooltip: 'কল',
                        onPressed: () => openDialer(context, entity),
                        icon: const Icon(Icons.call_rounded),
                      ),
                      IconButton(
                        tooltip: 'রিমাইন্ডার',
                        onPressed: () => showReminderSheet(context, entity),
                        icon: const Icon(Icons.notifications_rounded),
                      ),
                      IconButton(
                        tooltip: 'ডিলিট',
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            '${entity.name} মুছে ফেলবেন?',
                          );
                          if (ok && context.mounted) {
                            await context.read<LedgerController>().deleteEntity(
                              entity.id,
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.delete_rounded,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.entityId});

  final String entityId;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  var _tab = TransactionType.debt;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final entity = controller.entities.firstWhere(
      (e) => e.id == widget.entityId,
    );
    final total = controller.entityTotal(entity.id);
    final entityTransactions = controller.transactionsFor(entity.id);
    final transactions = _tab == TransactionType.debt
        ? entityTransactions
        : entityTransactions
              .where((tx) => tx.type == TransactionType.payment)
              .toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          entity.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryContainer],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 126,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        taka(total),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'মোট বকেয়া / ব্যালেন্স',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: EntityIdentityDetails(
                    entity: entity,
                    labelColor: Colors.white70,
                    valueColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showTransactionSheet(
                    context,
                    entity,
                    TransactionType.debt,
                  ),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('দেনা/আইটেম যোগ'),
                  style: primaryButtonStyle(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showTransactionSheet(
                    context,
                    entity,
                    TransactionType.payment,
                  ),
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('পেমেন্ট'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(
                value: TransactionType.debt,
                label: Text('দেনার বিবরণ'),
                icon: Icon(Icons.list_alt_rounded),
              ),
              ButtonSegment(
                value: TransactionType.payment,
                label: Text('পরিশোধিত'),
                icon: Icon(Icons.done_all_rounded),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
          const SizedBox(height: 14),
          if (transactions.isEmpty)
            EmptyState(
              icon: _tab == TransactionType.debt
                  ? Icons.receipt_long_rounded
                  : Icons.payments_rounded,
              title: 'লেনদেন নেই',
              subtitle: 'উপরের বাটন থেকে নতুন তথ্য যোগ করুন',
            )
          else
            ...transactions.map(
              (tx) => TransactionCard(
                transaction: tx,
                showActions: true,
                showTypeLabel: _tab == TransactionType.debt,
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: .94),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'মোট বকেয়া পরিমাণ',
                      style: TextStyle(color: Colors.white60),
                    ),
                    Text(
                      taka(total),
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => shareEntityBalance(context, entity, total),
                icon: const Icon(Icons.share_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataFileScreenState();
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final moduleTotals = controller.moduleTotals;
    final monthlyTotals = controller.monthlyTransactionTotals();
    final topEntities = controller.topEntities();
    final maxModule = moduleTotals.values.fold<double>(
      1,
      (max, value) => value > max ? value : max,
    );
    final maxMonthly = monthlyTotals.values.fold<double>(
      1,
      (max, value) => value > max ? value : max,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryContainer],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'রিপোর্ট',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'লেনদেন, দেনা, পাওনা ও আমানতের সারাংশ',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ReportMetric(
                      label: 'সর্বমোট দেনা',
                      value: taka(controller.allDebt),
                      color: AppColors.errorSoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ReportMetric(
                      label: 'মোট পাওনা',
                      value: taka(controller.receivable),
                      color: AppColors.successSoft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ReportSection(
          title: 'মডিউল অনুযায়ী হিসাব',
          child: Column(
            children: LedgerType.values.map((type) {
              final value = moduleTotals[type] ?? 0;
              return ReportBarRow(
                label: type.totalTitle,
                value: value,
                maxValue: maxModule,
                color: type.isPositive ? AppColors.success : AppColors.error,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        ReportSection(
          title: 'মাসিক লেনদেন',
          child: SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: monthlyTotals.entries.map((entry) {
                final ratio = (entry.value / maxMonthly).clamp(0.04, 1.0);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          taka(entry.value),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: ratio,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 18),
        ReportSection(
          title: 'শীর্ষ ব্যালেন্স',
          child: Column(
            children: topEntities.map((entity) {
              final total = controller.entityTotal(entity.id);
              final color = entity.type.isPositive
                  ? AppColors.success
                  : AppColors.error;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 108,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            taka(total),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'ব্যালেন্স',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: EntityIdentityDetails(entity: entity)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class ReportMetric extends StatelessWidget {
  const ReportMetric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ReportSection extends StatelessWidget {
  const ReportSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softDecoration(AppColors.white, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class ReportBarRow extends StatelessWidget {
  const ReportBarRow({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final double value;
  final double maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                taka(value),
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: ratio,
              backgroundColor: AppColors.surfaceLow,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataFileScreenState extends State<DataScreen> {
  final _json = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 110),
      children: [
        const Icon(Icons.storage_rounded, color: AppColors.accent, size: 80),
        const SizedBox(height: 14),
        const Text(
          'ডেটা ব্যাকআপ ও রিস্টোর',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'আপনার হিসাব JSON ফাইল হিসেবে এক্সপোর্ট বা ইম্পোর্ট করুন।',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        DataActionCard(
          icon: Icons.upload_rounded,
          title: 'Export JSON',
          subtitle: 'JSON ফাইল তৈরি করে শেয়ার করুন',
          primary: true,
          onTap: _busy ? null : _exportFile,
        ),
        const SizedBox(height: 14),
        DataActionCard(
          icon: Icons.download_rounded,
          title: 'Import JSON',
          subtitle: 'ফাইল থেকে ব্যাকআপ রিস্টোর করুন',
          onTap: _busy ? null : _importFile,
        ),
        const SizedBox(height: 14),
        DataActionCard(
          icon: Icons.code_rounded,
          title: 'JSON Text',
          subtitle: 'ম্যানুয়ালি কপি/পেস্ট করে ব্যাকআপ নিন',
          onTap: () {
            _json.text = context.read<LedgerController>().exportJson();
            showSnack(context, 'JSON টেক্সট তৈরি হয়েছে');
          },
        ),
        const SizedBox(height: 14),
        DataActionCard(
          icon: Icons.restore_page_rounded,
          title: 'Import Text',
          subtitle: 'বক্সের JSON থেকে রিস্টোর করুন',
          onTap: _busy ? null : _importText,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _json,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: 'JSON ডাটা এখানে থাকবে',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: softDecoration(AppColors.surfaceLow, 20),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_rounded, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'JSON ফাইল অন্য কারো সাথে শেয়ার করবেন না। ইম্পোর্ট করলে বর্তমান ডাটা বদলে যেতে পারে।',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportFile() async {
    setState(() => _busy = true);
    try {
      final file = await context.read<LedgerController>().exportJsonFile();
      _json.text = await file.readAsString(encoding: utf8);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'দেনা পাওনা JSON backup'),
      );
      if (mounted) showSnack(context, 'JSON ফাইল তৈরি হয়েছে');
    } catch (_) {
      if (mounted) showSnack(context, 'ফাইল এক্সপোর্ট করা যায়নি');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final ok = await confirmDialog(
      context,
      'এই ফাইল দিয়ে বর্তমান ডাটা বদলাবেন?',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final file = File(path);
      await context.read<LedgerController>().importJsonFile(file);
      _json.text = await file.readAsString(encoding: utf8);
      if (mounted) showSnack(context, 'JSON ফাইল ইম্পোর্ট হয়েছে');
    } catch (_) {
      if (mounted) showSnack(context, 'সঠিক JSON ফাইল দিন');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importText() async {
    final ok = await confirmDialog(
      context,
      'এই JSON দিয়ে বর্তমান ডাটা বদলাবেন?',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<LedgerController>().importJson(_json.text);
      if (mounted) showSnack(context, 'ডাটা ইম্পোর্ট হয়েছে');
    } catch (_) {
      if (mounted) showSnack(context, 'সঠিক JSON দিন');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// Kept temporarily for migration safety; DataScreen now uses _DataFileScreenState.
// ignore: unused_element
class _DataScreenState extends State<DataScreen> {
  final _json = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 110),
      children: [
        const Icon(Icons.storage_rounded, color: AppColors.accent, size: 80),
        const SizedBox(height: 14),
        const Text(
          'ডেটা ব্যাকআপ ও রিস্টোর',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'আপনার হিসাব JSON হিসেবে এক্সপোর্ট বা ইম্পোর্ট করুন।',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        DataActionCard(
          icon: Icons.upload_rounded,
          title: 'Export JSON',
          subtitle: 'ব্যাকআপ ডাটা নিচের বক্সে দেখুন',
          primary: true,
          onTap: () {
            _json.text = context.read<LedgerController>().exportJson();
            showSnack(context, 'JSON এক্সপোর্ট হয়েছে');
          },
        ),
        const SizedBox(height: 14),
        DataActionCard(
          icon: Icons.download_rounded,
          title: 'Import JSON',
          subtitle: 'বক্সে JSON বসিয়ে রিস্টোর করুন',
          onTap: () async {
            try {
              await context.read<LedgerController>().importJson(_json.text);
              if (context.mounted) showSnack(context, 'ডাটা ইম্পোর্ট হয়েছে');
            } catch (_) {
              if (context.mounted) showSnack(context, 'সঠিক JSON দিন');
            }
          },
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _json,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: 'JSON ডাটা এখানে থাকবে',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: softDecoration(AppColors.surfaceLow, 20),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_rounded, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'JSON ফাইল অন্য কারো সাথে শেয়ার করবেন না। ইম্পোর্ট করলে বর্তমান ডাটা বদলে যেতে পারে।',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DataActionCard extends StatelessWidget {
  const DataActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: softDecoration(
          primary ? AppColors.primary : AppColors.white,
          24,
        ),
        child: Row(
          children: [
            IconBadge(
              icon: icon,
              color: primary ? Colors.white : AppColors.primary,
              background: primary
                  ? Colors.white.withValues(alpha: .12)
                  : AppColors.accent,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: primary ? Colors.white : AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: primary ? Colors.white70 : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: primary ? Colors.white54 : AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionCard extends StatelessWidget {
  const TransactionCard({
    super.key,
    required this.transaction,
    this.showActions = false,
    this.showTypeLabel = false,
  });

  final LedgerTransaction transaction;
  final bool showActions;
  final bool showTypeLabel;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LedgerController>();
    final entity = controller.entities
        .where((item) => item.id == transaction.entityId)
        .firstOrNull;
    final isPayment = transaction.type == TransactionType.payment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: softDecoration(AppColors.white, 20),
        child: Row(
          children: [
            IconBadge(
              icon: isPayment
                  ? Icons.payments_rounded
                  : Icons.shopping_bag_rounded,
              color: isPayment ? AppColors.success : AppColors.error,
              background: isPayment
                  ? AppColors.successSoft
                  : AppColors.errorSoft,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description.isEmpty
                        ? (entity?.name ?? 'লেনদেন')
                        : transaction.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    [
                      if (showTypeLabel) isPayment ? 'পরিশোধ' : 'দেনা',
                      if (entity != null) entity.name,
                      dateText(transaction.date),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isPayment ? '-' : '+'}${taka(transaction.amount)}',
                  style: TextStyle(
                    color: isPayment ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (showActions)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'এডিট',
                        visualDensity: VisualDensity.compact,
                        onPressed: entity == null
                            ? null
                            : () => showTransactionSheet(
                                context,
                                entity,
                                transaction.type,
                                transaction: transaction,
                              ),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                      ),
                      IconButton(
                        tooltip: 'ডিলিট',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            'এই লেনদেন মুছে ফেলবেন?',
                          );
                          if (ok && context.mounted) {
                            await context
                                .read<LedgerController>()
                                .deleteTransaction(transaction.id);
                          }
                        },
                        icon: const Icon(
                          Icons.delete_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: softDecoration(AppColors.surfaceLow, 24),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 46),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.background,
  });

  final IconData icon;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

Future<void> showEntitySheet(
  BuildContext context,
  LedgerType type, {
  LedgerEntity? entity,
}) async {
  final name = TextEditingController(text: entity?.name ?? '');
  final fatherName = TextEditingController(text: entity?.fatherName ?? '');
  final address = TextEditingController(text: entity?.address ?? '');
  final phone = TextEditingController(text: entity?.phone ?? '');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SheetFrame(
        title: entity == null ? 'নতুন ${type.title} যোগ করুন' : 'তথ্য এডিট',
        icon: type.icon,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'নাম'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fatherName,
            decoration: const InputDecoration(labelText: 'পিতার নাম'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: address,
            minLines: 1,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ঠিকানা'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'ফোন নম্বর'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                showSnack(sheetContext, 'নাম দিন');
                return;
              }
              final controller = context.read<LedgerController>();
              if (entity == null) {
                await controller.addEntity(
                  type,
                  name.text,
                  phone.text,
                  fatherName: fatherName.text,
                  address: address.text,
                );
              } else {
                await controller.updateEntity(
                  entity,
                  name.text,
                  phone.text,
                  fatherName: fatherName.text,
                  address: address.text,
                );
              }
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('সংরক্ষণ করুন'),
            style: primaryButtonStyle(),
          ),
        ],
      );
    },
  );
}

Future<void> showReminderSheet(
  BuildContext context,
  LedgerEntity entity,
) async {
  final note = TextEditingController(text: entity.reminderNote);
  final selectedDate = ValueNotifier<DateTime?>(
    entity.reminderAt ?? DateTime.now().add(const Duration(days: 1)),
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SheetFrame(
        title: 'রিমাইন্ডার',
        icon: Icons.notifications_active_rounded,
        children: [
          ValueListenableBuilder<DateTime?>(
            valueListenable: selectedDate,
            builder: (_, value, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('তারিখ'),
              subtitle: Text(value == null ? 'তারিখ নেই' : dateText(value)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: () async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  initialDate: value ?? DateTime.now(),
                );
                if (picked != null) selectedDate.value = picked;
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'নোট'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () async {
              await context.read<LedgerController>().updateReminder(
                entity,
                reminderAt: selectedDate.value,
                reminderNote: note.text,
              );
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('রিমাইন্ডার সংরক্ষণ'),
            style: primaryButtonStyle(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    await context.read<LedgerController>().updateReminder(
                      entity,
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('মুছুন'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: entity.reminderAt == null
                      ? null
                      : () async {
                          await context
                              .read<LedgerController>()
                              .completeReminder(entity);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

Future<void> sendReminderSms(BuildContext context, LedgerEntity entity) async {
  final controller = context.read<LedgerController>();
  final phone = normalizedPhoneForIntent(entity.phone);
  final message = controller.reminderMessage(entity);
  if (phone.isEmpty) {
    await SharePlus.instance.share(ShareParams(text: message));
    return;
  }
  final uri = Uri(
    scheme: 'sms',
    path: phone,
    queryParameters: {'body': message},
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    await SharePlus.instance.share(ShareParams(text: message));
  }
}

Future<void> openDialer(BuildContext context, LedgerEntity entity) async {
  final phone = normalizedPhoneForIntent(entity.phone);
  if (phone.isEmpty) {
    showSnack(context, 'ফোন নম্বর নেই');
    return;
  }
  final uri = Uri(scheme: 'tel', path: phone);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    showSnack(context, 'ডায়ালার খোলা যায়নি');
  }
}

Future<void> shareEntityBalance(
  BuildContext context,
  LedgerEntity entity,
  double total,
) async {
  final text = [
    'দেনা-পাওনা তথ্য',
    '',
    'নাম: ${displayOrDash(entity.name)}',
    'পিতার নাম: ${displayOrDash(entity.fatherName)}',
    'ঠিকানা: ${displayOrDash(entity.address)}',
    'ফোন নম্বর: ${displayOrDash(entity.phone)}',
    '',
    'মোট বকেয়া/ব্যালেন্স: ${taka(total)}',
    '',
    'তারিখ: ${dateText(DateTime.now())}',
  ].join('\n');

  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'শেয়ার করা যায়নি');
    }
  }
}

Future<void> showTransactionSheet(
  BuildContext context,
  LedgerEntity entity,
  TransactionType type, {
  LedgerTransaction? transaction,
}) async {
  final isEdit = transaction != null;
  final description = TextEditingController(
    text: transaction?.description ?? '',
  );
  final amount = TextEditingController(
    text: transaction == null ? '' : transaction.amount.toStringAsFixed(0),
  );
  var method = 'নগদ';
  final date = ValueNotifier(transaction?.date ?? DateTime.now());
  final itemDrafts = ValueNotifier<List<_DetailItemDraft>>(
    transaction?.subItems.isNotEmpty == true
        ? transaction!.subItems
              .map(
                (item) => _DetailItemDraft(
                  name: item.name,
                  amount: item.amount.toStringAsFixed(0),
                ),
              )
              .toList()
        : <_DetailItemDraft>[],
  );

  void updateDraftTotal() {
    final total = detailItemsTotal(
      itemDrafts.value
          .map((draft) => draft.toDetailItem())
          .whereType<DetailItem>()
          .toList(),
    );
    if (total > 0) amount.text = total.toStringAsFixed(0);
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SheetFrame(
        title: type == TransactionType.debt ? 'নতুন আইটেম' : 'টাকা জমা',
        icon: type == TransactionType.debt
            ? Icons.receipt_long_rounded
            : Icons.payments_rounded,
        children: [
          TextField(
            controller: description,
            decoration: InputDecoration(
              labelText: type == TransactionType.debt ? 'বিবরণ' : 'নোট',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'পরিমাণ (৳)'),
          ),
          const SizedBox(height: 12),
          if (type == TransactionType.debt)
            ValueListenableBuilder<List<_DetailItemDraft>>(
              valueListenable: itemDrafts,
              builder: (context, drafts, _) {
                final total = detailItemsTotal(
                  drafts
                      .map((draft) => draft.toDetailItem())
                      .whereType<DetailItem>()
                      .toList(),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'আইটেম লিস্ট',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            itemDrafts.value = [...drafts, _DetailItemDraft()];
                          },
                          icon: const Icon(Icons.add_circle_rounded),
                          label: const Text('আইটেম'),
                        ),
                      ],
                    ),
                    ...drafts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final draft = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: draft.name,
                                decoration: InputDecoration(
                                  labelText: 'আইটেম ${index + 1}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: draft.amount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '৳',
                                ),
                                onChanged: (_) {
                                  updateDraftTotal();
                                  itemDrafts.value = [...itemDrafts.value];
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'মুছুন',
                              onPressed: () {
                                draft.dispose();
                                itemDrafts.value = [
                                  ...drafts.where((item) => item != draft),
                                ];
                                updateDraftTotal();
                              },
                              icon: const Icon(
                                Icons.delete_rounded,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (drafts.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: softDecoration(AppColors.primary, 18),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'মোট পরিমাণ',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              taka(total),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          if (type == TransactionType.payment)
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'পদ্ধতি'),
              items: const ['নগদ', 'বিকাশ', 'নগদ মোবাইল', 'ব্যাংক']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => method = value ?? method,
            ),
          if (type == TransactionType.payment) const SizedBox(height: 12),
          ValueListenableBuilder<DateTime>(
            valueListenable: date,
            builder: (_, value, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('তারিখ'),
              subtitle: Text(dateText(value)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: () async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  initialDate: value,
                );
                if (picked != null) date.value = picked;
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final subItems = type == TransactionType.debt
                  ? itemDrafts.value
                        .map((draft) => draft.toDetailItem())
                        .whereType<DetailItem>()
                        .toList()
                  : <DetailItem>[];
              final subItemsTotal = detailItemsTotal(subItems);
              if (subItems.isNotEmpty) {
                amount.text = subItemsTotal.toStringAsFixed(0);
              }
              final parsed = double.tryParse(amount.text.trim());
              if (parsed == null || parsed <= 0) {
                showSnack(sheetContext, 'সঠিক পরিমাণ দিন');
                return;
              }
              final controller = context.read<LedgerController>();
              if (!isEdit) {
                await controller.addTransaction(
                  entityId: entity.id,
                  type: type,
                  description: description.text,
                  amount: parsed,
                  date: date.value,
                  method: method,
                  subItems: subItems,
                );
              } else {
                await controller.updateTransaction(
                  id: transaction.id,
                  type: type,
                  description: description.text,
                  amount: parsed,
                  date: date.value,
                  method: method,
                  subItems: subItems.isEmpty ? transaction.subItems : subItems,
                );
              }
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('সংরক্ষণ করুন'),
            style: type == TransactionType.debt
                ? primaryButtonStyle()
                : FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
          ),
        ],
      );
    },
  );
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        decoration: const BoxDecoration(
          color: AppColors.surfaceLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(icon: icon, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration softDecoration(Color color, double radius) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: color == AppColors.white ? softShadow : null,
  );
}

List<BoxShadow> get softShadow => [
  BoxShadow(
    color: AppColors.primary.withValues(alpha: .08),
    blurRadius: 24,
    offset: const Offset(0, 8),
  ),
];

ButtonStyle primaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
  );
}

final NumberFormat _takaFormatter = NumberFormat.decimalPattern('en_US');
final DateFormat _dateTextFormatter = DateFormat('dd/MM/yyyy');

String taka(double amount) {
  return '৳ ${_takaFormatter.format(amount.round())}';
}

String dateText(DateTime date) {
  return _dateTextFormatter.format(date);
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> confirmDialog(BuildContext context, String title) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('না'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('হ্যাঁ'),
            ),
          ],
        ),
      ) ??
      false;
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
