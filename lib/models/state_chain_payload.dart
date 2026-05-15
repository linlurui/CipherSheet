import 'dart:convert';

import 'ledger.dart';
import 'bill.dart';
import 'settlement.dart';

/// 写入 DecentriLicense Token 的 state_payload 的载荷。
///
/// 注意：根据 DL 设计（Token 容量受限、签名验证开销随 payload 增大而变高），
/// 这里**只存摘要 (hash + 元数据)** 而非金额明文。
/// 完整明细放在本地加密存储，state_payload 仅作"防篡改公证"。
class StateChainPayload {
  final String version;
  final int stateIndex;
  final String? prevHash;
  final List<Ledger> ledgers;
  /// ledgerId -> bill摘要列表 (每个bill含其cell摘要)
  final Map<String, List<Map<String, dynamic>>> billDigests;
  final Map<String, Settlement?> latestSettlements;
  final DateTime updatedAt;

  StateChainPayload({
    this.version = '2.0',
    required this.stateIndex,
    this.prevHash,
    required this.ledgers,
    required this.billDigests,
    required this.latestSettlements,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'version': version,
        'state_index': stateIndex,
        'prev_hash': prevHash,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'ledgers': ledgers.map((l) => l.toJson()).toList(),
        'bill_digests': billDigests,
        'latest_settlements':
            latestSettlements.map((k, v) => MapEntry(k, v?.toJson())),
      };

  String toJsonString() => jsonEncode(toJson());

  factory StateChainPayload.fromJson(Map<String, dynamic> j) {
    final ledgers = ((j['ledgers'] as List?) ?? [])
        .map((e) => Ledger.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final rawDigests = (j['bill_digests'] as Map?) ?? {};
    final digests = <String, List<Map<String, dynamic>>>{};
    rawDigests.forEach((k, v) {
      digests[k as String] = ((v as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
    final rawSettlements = (j['latest_settlements'] as Map?) ?? {};
    final settlements = <String, Settlement?>{};
    rawSettlements.forEach((k, v) {
      settlements[k as String] = v == null
          ? null
          : Settlement.fromJson(Map<String, dynamic>.from(v as Map));
    });
    return StateChainPayload(
      version: (j['version'] as String?) ?? '2.0',
      stateIndex: (j['state_index'] as int?) ?? 0,
      prevHash: j['prev_hash'] as String?,
      ledgers: ledgers,
      billDigests: digests,
      latestSettlements: settlements,
      updatedAt: j['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(j['updated_at'] as int)
          : null,
    );
  }

  static StateChainPayload? tryParse(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) return StateChainPayload.fromJson(j);
    } catch (_) {}
    return null;
  }

  /// 从一组账本视图构造 payload（含 bill + cell 摘要）
  static StateChainPayload fromViews(
    List<LedgerView> views, {
    required int stateIndex,
    String? prevHash,
  }) {
    final ledgers = views.map((v) => v.ledger).toList();
    final digests = <String, List<Map<String, dynamic>>>{};
    final settlements = <String, Settlement?>{};
    for (final v in views) {
      final billList = <Map<String, dynamic>>[];
      for (final bill in v.bills) {
        billList.add({
          'bill_id': bill.billId,
          'order_index': bill.orderIndex,
          'title': bill.title,
          'cell_count': bill.cells.length,
          'cell_digests': bill.cells.map((c) => c.toDigest()).toList(),
        });
      }
      digests[v.ledger.id] = billList;
      settlements[v.ledger.id] = v.latestSettlement;
    }
    return StateChainPayload(
      stateIndex: stateIndex,
      prevHash: prevHash,
      ledgers: ledgers,
      billDigests: digests,
      latestSettlements: settlements,
    );
  }
}

/// 完整本地存储载荷（包含明文账单/格子/结算）。
/// 持久化到本地加密文件；不写入 Token。
class LocalLedgerStore {
  final List<Ledger> ledgers;
  final Map<String, List<Bill>> bills;                  // ledgerId -> bills(含cells)
  final Map<String, List<Settlement>> settlements;      // ledgerId -> history

  /// 全局助记词校验哈希（PBKDF2 salt:hash，所有账本共用一个助记词）
  String? mnemonicVerifier;

  /// 全局助记词是否已启用
  bool mnemonicEnabled;

  LocalLedgerStore({
    required this.ledgers,
    required this.bills,
    required this.settlements,
    this.mnemonicVerifier,
    this.mnemonicEnabled = false,
  });

  factory LocalLedgerStore.empty() =>
      LocalLedgerStore(ledgers: [], bills: {}, settlements: {});

  Map<String, dynamic> toJson() => {
        'ledgers': ledgers.map((l) => l.toJson()).toList(),
        'bills': bills
            .map((k, v) => MapEntry(k, v.map((b) => b.toJson()).toList())),
        'settlements': settlements
            .map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())),
        'mnemonic_verifier': mnemonicVerifier,
        'mnemonic_enabled': mnemonicEnabled,
      };

  factory LocalLedgerStore.fromJson(Map<String, dynamic> j) {
    final ledgers = ((j['ledgers'] as List?) ?? [])
        .map((e) => Ledger.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final bills = <String, List<Bill>>{};
    ((j['bills'] as Map?) ?? {}).forEach((k, v) {
      bills[k as String] = ((v as List?) ?? [])
          .map((e) => Bill.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
    final settlements = <String, List<Settlement>>{};
    ((j['settlements'] as Map?) ?? {}).forEach((k, v) {
      settlements[k as String] = ((v as List?) ?? [])
          .map((e) => Settlement.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
    // 兼容旧版：如果 ledgers[0] 有 mnemonic_verifier，迁移到全局
    String? globalVerifier = j['mnemonic_verifier'] as String?;
    bool globalEnabled = (j['mnemonic_enabled'] as bool?) ?? false;
    if (globalVerifier == null && ledgers.isNotEmpty) {
      // 迁移：从第一个有 mnemonic 的 ledger 提取
      for (final l in ledgers) {
        final mv = (l.toJson())['mnemonic_verifier'] as String?;
        if (mv != null) {
          globalVerifier = mv;
          globalEnabled = true;
          break;
        }
      }
    }
    return LocalLedgerStore(
        ledgers: ledgers, bills: bills, settlements: settlements,
        mnemonicVerifier: globalVerifier, mnemonicEnabled: globalEnabled);
  }
}
