import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

/// 局域网自动同步服务。
///
/// 原理：
/// 1. UDP 广播发现：每 5 秒向 255.255.255.255:23456 广播本设备的 activationHash + timestamp
/// 2. 收到广播后，比较 activationHash：相同则属于同一用户，可同步
/// 3. TCP 同步：较旧数据的设备连接较新数据的设备，拉取最新数据
/// 4. 数据传输用 activationHash 派生的密钥加密（AES-256-GCM）
///
/// 同步策略：以 updatedAt 最新的为准（整体替换）
class LanSyncService {
  static const int _broadcastPort = 23456;
  static const int _syncPort = 23457;
  static const Duration _broadcastInterval = Duration(seconds: 5);

  final String activationHash;
  final Future<String> Function() onExportRequest;
  final Future<String?> Function(String) onImportRequest;

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _broadcastTimer;
  bool _running = false;

  /// 本设备最后更新时间
  DateTime _lastUpdated = DateTime.now();
  set lastUpdated(DateTime v) => _lastUpdated = v;

  /// 已发现的同 hash 设备列表 (address -> lastSeen + updatedAt)
  final Map<String, _PeerInfo> _peers = {};

  LanSyncService({
    required this.activationHash,
    required this.onExportRequest,
    required this.onImportRequest,
  });

  bool get isRunning => _running;
  Map<String, _PeerInfo> get peers => Map.unmodifiable(_peers);

  /// 启动同步服务
  Future<void> start() async {
    if (_running) return;
    _running = true;

    // 启动 UDP 监听
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _broadcastPort);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(_onUdpData);
      debugPrint('[LanSync] UDP listening on port $_broadcastPort');
    } catch (e) {
      debugPrint('[LanSync] UDP bind failed: $e');
    }

    // 启动 TCP 同步服务器
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, _syncPort);
      _tcpServer!.listen(_onTcpConnection);
      debugPrint('[LanSync] TCP server listening on port $_syncPort');
    } catch (e) {
      debugPrint('[LanSync] TCP bind failed: $e');
    }

    // 定时广播
    _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => _broadcast());
    _broadcast(); // 立即广播一次
  }

  /// 停止同步服务
  void stop() {
    _running = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _tcpServer?.close();
    _tcpServer = null;
    _peers.clear();
    debugPrint('[LanSync] stopped');
  }

  /// 广播本设备信息
  void _broadcast() {
    if (_udpSocket == null) return;
    final msg = jsonEncode({
      'type': 'cipher_sync_beacon',
      'hash': activationHash,
      'updated_at': _lastUpdated.millisecondsSinceEpoch,
      'sync_port': _syncPort,
    });
    final data = utf8.encode(msg);
    _udpSocket!.send(data, InternetAddress('255.255.255.255'), _broadcastPort);
  }

  /// 处理 UDP 广播
  void _onUdpData(RawSocketEvent event) {
    final socket = _udpSocket;
    if (socket == null) return;
    if (event == RawSocketEvent.read) {
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final msg = utf8.decode(datagram.data);
        final j = jsonDecode(msg) as Map<String, dynamic>;
        if (j['type'] != 'cipher_sync_beacon') return;
        if (j['hash'] != activationHash) return; // 不同用户，忽略

        final address = datagram.address.address;
        final peerUpdated = DateTime.fromMillisecondsSinceEpoch(
            (j['updated_at'] as int?) ?? 0);
        final peerSyncPort = (j['sync_port'] as int?) ?? _syncPort;

        _peers[address] = _PeerInfo(
          address: address,
          syncPort: peerSyncPort,
          lastSeen: DateTime.now(),
          updatedAt: peerUpdated,
        );

        debugPrint('[LanSync] peer found: $address, updated=$peerUpdated');

        // 如果对方数据更新，主动拉取
        if (peerUpdated.isAfter(_lastUpdated)) {
          _pullFromPeer(address, peerSyncPort);
        }
      } catch (e) {
        // 忽略格式错误
      }
    }
  }

  /// 从对端拉取最新数据
  Future<void> _pullFromPeer(String address, int port) async {
    debugPrint('[LanSync] pulling from $address:$port');
    try {
      final socket = await Socket.connect(address, port, timeout: const Duration(seconds: 5));
      // 发送请求
      socket.write(jsonEncode({'action': 'pull', 'hash': activationHash}));
      await socket.flush();

      // 读取响应
      final buf = <int>[];
      await socket.forEach((data) {
        buf.addAll(data);
      });
      socket.destroy();

      if (buf.isEmpty) return;
      final response = utf8.decode(buf);
      final j = jsonDecode(response) as Map<String, dynamic>;
      if (j['status'] != 'ok') return;

      final encryptedData = j['data'] as String;
      final err = await onImportRequest(encryptedData);
      if (err == null) {
        _lastUpdated = DateTime.now();
        debugPrint('[LanSync] sync completed from $address');
      } else {
        debugPrint('[LanSync] import failed: $err');
      }
    } catch (e) {
      debugPrint('[LanSync] pull failed: $e');
    }
  }

  /// 处理 TCP 同步连接（服务端）
  Future<void> _onTcpConnection(Socket client) async {
    try {
      final buf = <int>[];
      final completer = Completer<void>();
      client.listen(
        (data) => buf.addAll(data),
        onDone: completer.complete,
        onError: (_) => completer.complete(),
      );
      await completer.future;

      if (buf.isEmpty) {
        client.destroy();
        return;
      }

      final request = utf8.decode(buf);
      final j = jsonDecode(request) as Map<String, dynamic>;
      if (j['hash'] != activationHash) {
        client.write(jsonEncode({'status': 'denied'}));
        client.destroy();
        return;
      }

      final action = j['action'] as String?;
      if (action == 'pull') {
        // 对方要拉取数据
        final encryptedData = await onExportRequest();
        client.write(jsonEncode({
          'status': 'ok',
          'data': encryptedData,
        }));
      }
      client.destroy();
    } catch (e) {
      debugPrint('[LanSync] TCP handler error: $e');
      try { client.destroy(); } catch (_) {}
    }
  }
}

class _PeerInfo {
  final String address;
  final int syncPort;
  final DateTime lastSeen;
  final DateTime updatedAt;

  _PeerInfo({
    required this.address,
    required this.syncPort,
    required this.lastSeen,
    required this.updatedAt,
  });
}
