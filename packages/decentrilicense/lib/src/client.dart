import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'ffi_bindings.dart';

/// High-level Dart wrapper for DecentriLicense client via dl-core FFI
class DecentriLicenseClient {
  final DecentriLicenseNative _native;
  Pointer<Void>? _clientPtr;
  bool _initialized = false;

  DecentriLicenseClient({String? libraryPath})
      : _native = libraryPath != null
            ? DecentriLicenseNative.fromPath(libraryPath)
            : DecentriLicenseNative() {
    _clientPtr = _native.dlClientCreate();
    if (_clientPtr == nullptr) {
      throw LicenseException('Failed to create client');
    }
  }

  bool get isInitialized => _initialized;

  /// Initialize the client with configuration
  void initialize({
    String licenseCode = '',
    int udpPort = 13325,
    int tcpPort = 23325,
    String registryServerUrl = '',
  }) {
    if (_clientPtr == null || _clientPtr == nullptr) {
      throw LicenseException('Client not created');
    }

    final configPtr = calloc<DLClientConfig>();
    try {
      configPtr.ref.license_code = licenseCode.toNativeUtf8().cast<Char>();
      configPtr.ref.preferred_mode = 0; // DL_CONNECTION_MODE_WAN_REGISTRY
      configPtr.ref.udp_port = udpPort;
      configPtr.ref.tcp_port = tcpPort;
      configPtr.ref.registry_server_url = registryServerUrl.toNativeUtf8().cast<Char>();

      final rc = _native.dlClientInitialize(_clientPtr!, configPtr);
      if (rc != 0) {
        throw LicenseException('Initialize failed with error code: $rc');
      }
      _initialized = true;
    } finally {
      calloc.free(configPtr.ref.license_code);
      calloc.free(configPtr.ref.registry_server_url);
      calloc.free(configPtr);
    }
  }

  /// Set the product public key (PEM content)
  void setProductPublicKey(String content) {
    _checkInitialized();
    final contentPtr = content.toNativeUtf8().cast<Char>();
    try {
      final rc = _native.dlClientSetProductPublicKey(_clientPtr!, contentPtr);
      if (rc != 0) {
        throw LicenseException('SetProductPublicKey failed with error code: $rc');
      }
    } finally {
      calloc.free(contentPtr);
    }
  }

  /// Import a token (encrypted string or JSON)
  void importToken(String tokenInput) {
    _checkInitialized();
    final inputPtr = tokenInput.toNativeUtf8().cast<Char>();
    try {
      final rc = _native.dlClientImportToken(_clientPtr!, inputPtr);
      if (rc != 0) {
        throw LicenseException('ImportToken failed with error code: $rc');
      }
    } finally {
      calloc.free(inputPtr);
    }
  }

  /// Offline verify the current token
  VerificationResult offlineVerifyCurrentToken() {
    _checkInitialized();
    final resultPtr = calloc<DLVerificationResult>();
    try {
      final rc = _native.dlClientOfflineVerify(_clientPtr!, resultPtr);
      if (rc != 0) {
        throw LicenseException('OfflineVerify failed with error code: $rc');
      }
      return VerificationResult._fromNative(resultPtr.ref);
    } finally {
      calloc.free(resultPtr);
    }
  }

  /// Get client status
  StatusResult getStatus() {
    _checkInitialized();
    final statusPtr = calloc<DLStatusResult>();
    try {
      final rc = _native.dlClientGetStatus(_clientPtr!, statusPtr);
      if (rc != 0) {
        throw LicenseException('GetStatus failed with error code: $rc');
      }
      return StatusResult._fromNative(statusPtr.ref);
    } finally {
      calloc.free(statusPtr);
    }
  }

  /// Activate and bind device
  VerificationResult activateBindDevice() {
    _checkInitialized();
    final resultPtr = calloc<DLVerificationResult>();
    try {
      final rc = _native.dlClientActivateBindDevice(_clientPtr!, resultPtr);
      if (rc != 0) {
        throw LicenseException('ActivateBindDevice failed with error code: $rc');
      }
      return VerificationResult._fromNative(resultPtr.ref);
    } finally {
      calloc.free(resultPtr);
    }
  }

  /// Record usage / state change
  VerificationResult recordUsage(String payloadJson) {
    _checkInitialized();
    final payloadPtr = payloadJson.toNativeUtf8().cast<Char>();
    final resultPtr = calloc<DLVerificationResult>();
    try {
      final rc = _native.dlClientRecordUsage(_clientPtr!, payloadPtr, resultPtr);
      if (rc != 0) {
        throw LicenseException('RecordUsage failed with error code: $rc');
      }
      return VerificationResult._fromNative(resultPtr.ref);
    } finally {
      calloc.free(payloadPtr);
      calloc.free(resultPtr);
    }
  }

  /// Export current token as encrypted string
  String exportCurrentTokenEncrypted() {
    _checkInitialized();
    final bufPtr = calloc<Char>(8192);
    try {
      final rc = _native.dlClientExportCurrentTokenEncrypted(_clientPtr!, bufPtr, 8192);
      if (rc != 0) {
        throw LicenseException('ExportCurrentTokenEncrypted failed with error code: $rc');
      }
      return bufPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(bufPtr);
    }
  }

  /// Export activated token as encrypted string
  String exportActivatedTokenEncrypted() {
    _checkInitialized();
    final bufPtr = calloc<Char>(8192);
    try {
      final rc = _native.dlClientExportActivatedTokenEncrypted(_clientPtr!, bufPtr, 8192);
      if (rc != 0) {
        throw LicenseException('ExportActivatedTokenEncrypted failed with error code: $rc');
      }
      return bufPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(bufPtr);
    }
  }

  /// Export state-changed token as encrypted string
  String exportStateChangedTokenEncrypted() {
    _checkInitialized();
    final bufPtr = calloc<Char>(8192);
    try {
      final rc = _native.dlClientExportStateChangedTokenEncrypted(_clientPtr!, bufPtr, 8192);
      if (rc != 0) {
        throw LicenseException('ExportStateChangedTokenEncrypted failed with error code: $rc');
      }
      return bufPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(bufPtr);
    }
  }

  /// Check if the license is activated
  bool isActivated() {
    if (_clientPtr == null || _clientPtr == nullptr) return false;
    return _native.dlClientIsActivated(_clientPtr!) == 1;
  }

  /// Get device ID
  String getDeviceId() {
    _checkInitialized();
    final bufPtr = calloc<Char>(128);
    try {
      final rc = _native.dlClientGetDeviceId(_clientPtr!, bufPtr, 128);
      if (rc != 0) {
        throw LicenseException('GetDeviceId failed with error code: $rc');
      }
      return bufPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(bufPtr);
    }
  }

  /// Get device state
  String getDeviceState() {
    if (_clientPtr == null || _clientPtr == nullptr) return 'idle';
    final state = _native.dlClientGetDeviceState(_clientPtr!);
    switch (state) {
      case 1: return 'discovering';
      case 2: return 'electing';
      case 3: return 'coordinator';
      case 4: return 'follower';
      default: return 'idle';
    }
  }

  /// Get plaintext state_payload (decrypted from SEK if applicable)
  String getStatePayload({int bufSize = 65536}) {
    _checkInitialized();
    final bufPtr = calloc<Char>(bufSize);
    try {
      final rc = _native.dlClientGetStatePayload(_clientPtr!, bufPtr, bufSize);
      if (rc != 0) {
        throw LicenseException('GetStatePayload failed with error code: $rc');
      }
      return bufPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(bufPtr);
    }
  }

  /// Add a recovery channel (passphrase) wrapping the SEK
  VerificationResult addRecoveryChannel(String password) {
    _checkInitialized();
    final pwdPtr = password.toNativeUtf8().cast<Char>();
    final resPtr = calloc<DLVerificationResult>();
    try {
      final rc = _native.dlClientAddRecoveryChannel(_clientPtr!, pwdPtr, resPtr);
      if (rc != 0) {
        throw LicenseException('AddRecoveryChannel failed with error code: $rc');
      }
      return VerificationResult._fromNative(resPtr.ref);
    } finally {
      calloc.free(pwdPtr);
      calloc.free(resPtr);
    }
  }

  /// Remove the recovery channel
  VerificationResult removeRecoveryChannel() {
    _checkInitialized();
    final resPtr = calloc<DLVerificationResult>();
    try {
      final rc = _native.dlClientRemoveRecoveryChannel(_clientPtr!, resPtr);
      if (rc != 0) {
        throw LicenseException('RemoveRecoveryChannel failed with error code: $rc');
      }
      return VerificationResult._fromNative(resPtr.ref);
    } finally {
      calloc.free(resPtr);
    }
  }

  /// Get current token as JSON string
  String getCurrentTokenJson({int bufSize = 65536}) {
    _checkInitialized();
    final bufPtr = calloc<Char>(bufSize);
    try {
      final rc = _native.dlClientGetCurrentTokenJson(_clientPtr!, bufPtr, bufSize);
      if (rc != 0) {
        throw LicenseException('GetCurrentTokenJson failed with error code: $rc');
      }
      return bufPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(bufPtr);
    }
  }

  /// Activate using an offline token string (first-time or re-activation on new device)
  ActivationResult activateWithToken(String tokenString) {
    _checkInitialized();
    final tokPtr = tokenString.toNativeUtf8().cast<Char>();
    final resPtr = calloc<DLActivationResult>();
    try {
      final rc = _native.dlClientActivateWithToken(_clientPtr!, tokPtr, resPtr);
      if (rc != 0) {
        throw LicenseException('ActivateWithToken failed with error code: $rc');
      }
      return ActivationResult._fromNative(resPtr.ref);
    } finally {
      calloc.free(tokPtr);
      calloc.free(resPtr);
    }
  }

  /// Shutdown the client
  void shutdown() {
    if (_clientPtr == null || _clientPtr == nullptr) return;
    _native.dlClientShutdown(_clientPtr!);
    _native.dlClientDestroy(_clientPtr!);
    _clientPtr = nullptr;
    _initialized = false;
  }

  void _checkInitialized() {
    if (!_initialized || _clientPtr == null || _clientPtr == nullptr) {
      throw LicenseException('Client not initialized');
    }
  }
}

/// Verification result
class VerificationResult {
  final bool valid;
  final String errorMessage;

  VerificationResult._({required this.valid, required this.errorMessage});

  factory VerificationResult._fromNative(DLVerificationResult ref) {
    return VerificationResult._(
      valid: ref.valid == 1,
      errorMessage: _arrayToString(ref.error_message, 256),
    );
  }

  @override
  String toString() => 'VerificationResult(valid: $valid, error: $errorMessage)';
}

/// Status result
class StatusResult {
  final bool hasToken;
  final bool isActivated;
  final int issueTime;
  final int expireTime;
  final int stateIndex;
  final String tokenId;
  final String holderDeviceId;
  final String appId;
  final String licenseCode;

  StatusResult._({
    required this.hasToken,
    required this.isActivated,
    required this.issueTime,
    required this.expireTime,
    required this.stateIndex,
    required this.tokenId,
    required this.holderDeviceId,
    required this.appId,
    required this.licenseCode,
  });

  factory StatusResult._fromNative(DLStatusResult ref) {
    return StatusResult._(
      hasToken: ref.has_token == 1,
      isActivated: ref.is_activated == 1,
      issueTime: ref.issue_time,
      expireTime: ref.expire_time,
      stateIndex: ref.state_index,
      tokenId: _arrayToString(ref.token_id, 128),
      holderDeviceId: _arrayToString(ref.holder_device_id, 256),
      appId: _arrayToString(ref.app_id, 128),
      licenseCode: _arrayToString(ref.license_code, 128),
    );
  }

  @override
  String toString() => 'StatusResult(hasToken: $hasToken, activated: $isActivated, '
      'tokenId: $tokenId, licenseCode: $licenseCode, appId: $appId)';
}

/// Activation result
class ActivationResult {
  final bool success;
  final String message;

  ActivationResult._({required this.success, required this.message});

  ActivationResult({required this.success, required this.message});

  factory ActivationResult._fromNative(DLActivationResult ref) {
    return ActivationResult._(
      success: ref.success == 1,
      message: _arrayToString(ref.message, 256),
    );
  }

  @override
  String toString() => 'ActivationResult(success: $success, message: $message)';
}

/// License exception
class LicenseException implements Exception {
  final String message;
  LicenseException(this.message);

  @override
  String toString() => 'LicenseException: $message';
}

/// Helper: convert fixed-size Uint8 array to Dart String (null-terminated C string)
String _arrayToString(Array<Uint8> array, [int size = 256]) {
  final bytes = <int>[];
  for (int i = 0; i < size; i++) {
    final byte = array[i];
    if (byte == 0) break;
    bytes.add(byte);
  }
  return String.fromCharCodes(bytes);
}
