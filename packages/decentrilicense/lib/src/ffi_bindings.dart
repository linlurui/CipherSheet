import 'dart:ffi';
import 'dart:io' show File, Platform;

// ============================================================
// C struct definitions matching decenlicense_c.h
// ============================================================

/// DL_ClientConfig
final class DLClientConfig extends Struct {
  external Pointer<Char> license_code;
  @Int32()
  external int preferred_mode;
  @Uint16()
  external int udp_port;
  @Uint16()
  external int tcp_port;
  external Pointer<Char> registry_server_url;
}

/// DL_Token
final class DLToken extends Struct {
  @Array(128)
  external Array<Uint8> token_id;
  @Array(256)
  external Array<Uint8> holder_device_id;
  @Int64()
  external int issue_time;
  @Int64()
  external int expire_time;
  @Array(512)
  external Array<Uint8> signature;
  @Array(1024)
  external Array<Uint8> license_public_key;
  @Array(512)
  external Array<Uint8> root_signature;
  @Array(128)
  external Array<Uint8> app_id;
  @Array(128)
  external Array<Uint8> license_code;
}

/// DL_VerificationResult
final class DLVerificationResult extends Struct {
  @Int32()
  external int valid;
  @Array(256)
  external Array<Uint8> error_message;
}

/// DL_StatusResult
final class DLStatusResult extends Struct {
  @Int32()
  external int has_token;
  @Int32()
  external int is_activated;
  @Int64()
  external int issue_time;
  @Int64()
  external int expire_time;
  @Uint64()
  external int state_index;
  @Array(128)
  external Array<Uint8> token_id;
  @Array(256)
  external Array<Uint8> holder_device_id;
  @Array(128)
  external Array<Uint8> app_id;
  @Array(128)
  external Array<Uint8> license_code;
}

/// DL_ActivationResult
final class DLActivationResult extends Struct {
  @Int32()
  external int success;
  @Array(256)
  external Array<Uint8> message;
  external Pointer<DLToken> token;
}

// ============================================================
// Native function typedefs
// ============================================================

// dl_client_create
typedef DLClientCreateNative = Pointer<Void> Function();
typedef DLClientCreateDart = Pointer<Void> Function();

// dl_client_destroy
typedef DLClientDestroyNative = Void Function(Pointer<Void> client);
typedef DLClientDestroyDart = void Function(Pointer<Void> client);

// dl_client_initialize
typedef DLClientInitializeNative = Int32 Function(
    Pointer<Void> client, Pointer<DLClientConfig> config);
typedef DLClientInitializeDart = int Function(
    Pointer<Void> client, Pointer<DLClientConfig> config);

// dl_client_set_product_public_key
typedef DLClientSetProductPublicKeyNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> content);
typedef DLClientSetProductPublicKeyDart = int Function(
    Pointer<Void> client, Pointer<Char> content);

// dl_client_import_token
typedef DLClientImportTokenNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> token_input);
typedef DLClientImportTokenDart = int Function(
    Pointer<Void> client, Pointer<Char> token_input);

// dl_client_offline_verify_current_token
typedef DLClientOfflineVerifyNative = Int32 Function(
    Pointer<Void> client, Pointer<DLVerificationResult> result);
typedef DLClientOfflineVerifyDart = int Function(
    Pointer<Void> client, Pointer<DLVerificationResult> result);

// dl_client_get_status
typedef DLClientGetStatusNative = Int32 Function(
    Pointer<Void> client, Pointer<DLStatusResult> status);
typedef DLClientGetStatusDart = int Function(
    Pointer<Void> client, Pointer<DLStatusResult> status);

// dl_client_activate_bind_device
typedef DLClientActivateBindDeviceNative = Int32 Function(
    Pointer<Void> client, Pointer<DLVerificationResult> result);
typedef DLClientActivateBindDeviceDart = int Function(
    Pointer<Void> client, Pointer<DLVerificationResult> result);

// dl_client_record_usage
typedef DLClientRecordUsageNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> payload, Pointer<DLVerificationResult> result);
typedef DLClientRecordUsageDart = int Function(
    Pointer<Void> client, Pointer<Char> payload, Pointer<DLVerificationResult> result);

// dl_client_export_current_token_encrypted
typedef DLClientExportCurrentTokenEncryptedNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> out_buf, IntPtr out_buf_size);
typedef DLClientExportCurrentTokenEncryptedDart = int Function(
    Pointer<Void> client, Pointer<Char> out_buf, int out_buf_size);

// dl_client_export_activated_token_encrypted
typedef DLClientExportActivatedTokenEncryptedNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> out_buf, IntPtr out_buf_size);
typedef DLClientExportActivatedTokenEncryptedDart = int Function(
    Pointer<Void> client, Pointer<Char> out_buf, int out_buf_size);

// dl_client_export_state_changed_token_encrypted
typedef DLClientExportStateChangedTokenEncryptedNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> out_buf, IntPtr out_buf_size);
typedef DLClientExportStateChangedTokenEncryptedDart = int Function(
    Pointer<Void> client, Pointer<Char> out_buf, int out_buf_size);

// dl_client_activate
typedef DLClientActivateNative = Int32 Function(
    Pointer<Void> client, Pointer<DLActivationResult> result);
typedef DLClientActivateDart = int Function(
    Pointer<Void> client, Pointer<DLActivationResult> result);

// dl_client_is_activated
typedef DLClientIsActivatedNative = Int32 Function(Pointer<Void> client);
typedef DLClientIsActivatedDart = int Function(Pointer<Void> client);

// dl_client_get_device_id
typedef DLClientGetDeviceIdNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> buf, IntPtr buf_size);
typedef DLClientGetDeviceIdDart = int Function(
    Pointer<Void> client, Pointer<Char> buf, int buf_size);

// dl_client_get_device_state
typedef DLClientGetDeviceStateNative = Int32 Function(Pointer<Void> client);
typedef DLClientGetDeviceStateDart = int Function(Pointer<Void> client);

// dl_client_shutdown
typedef DLClientShutdownNative = Int32 Function(Pointer<Void> client);
typedef DLClientShutdownDart = int Function(Pointer<Void> client);

// dl_client_get_state_payload
typedef DLClientGetStatePayloadNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> out_buf, IntPtr out_buf_size);
typedef DLClientGetStatePayloadDart = int Function(
    Pointer<Void> client, Pointer<Char> out_buf, int out_buf_size);

// dl_client_add_recovery_channel
typedef DLClientAddRecoveryChannelNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> password, Pointer<DLVerificationResult> result);
typedef DLClientAddRecoveryChannelDart = int Function(
    Pointer<Void> client, Pointer<Char> password, Pointer<DLVerificationResult> result);

// dl_client_remove_recovery_channel
typedef DLClientRemoveRecoveryChannelNative = Int32 Function(
    Pointer<Void> client, Pointer<DLVerificationResult> result);
typedef DLClientRemoveRecoveryChannelDart = int Function(
    Pointer<Void> client, Pointer<DLVerificationResult> result);

// dl_client_get_current_token_json
typedef DLClientGetCurrentTokenJsonNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> out_buf, IntPtr out_buf_size);
typedef DLClientGetCurrentTokenJsonDart = int Function(
    Pointer<Void> client, Pointer<Char> out_buf, int out_buf_size);

// dl_client_activate_with_token
typedef DLClientActivateWithTokenNative = Int32 Function(
    Pointer<Void> client, Pointer<Char> token_str, Pointer<DLActivationResult> result);
typedef DLClientActivateWithTokenDart = int Function(
    Pointer<Void> client, Pointer<Char> token_str, Pointer<DLActivationResult> result);

// ============================================================
// Library binding class
// ============================================================

class DecentriLicenseNative {
  final DynamicLibrary _lib;

  DecentriLicenseNative() : _lib = _loadLibrary();

  static DynamicLibrary _loadLibrary() {
    if (Platform.isMacOS) {
      // @executable_path is resolved by macOS dyld to the dir of the main executable
      return DynamicLibrary.open('@executable_path/libdecentrilicense.dylib');
    } else if (Platform.isLinux) {
      final exeDir = File(Platform.executable).parent.path;
      final p = '$exeDir/libdecentrilicense.so';
      if (File(p).existsSync()) return DynamicLibrary.open(p);
      return DynamicLibrary.open('libdecentrilicense.so');
    } else if (Platform.isWindows) {
      final exeDir = File(Platform.executable).parent.path;
      final p = '$exeDir\\decentrilicense.dll';
      if (File(p).existsSync()) return DynamicLibrary.open(p);
      return DynamicLibrary.open('decentrilicense.dll');
    }
    throw UnsupportedError('Unsupported platform');
  }

  // Allow specifying a custom library path
  DecentriLicenseNative.fromPath(String path) : _lib = DynamicLibrary.open(path);

  late final DLClientCreateDart dlClientCreate =
      _lib.lookupFunction<DLClientCreateNative, DLClientCreateDart>(
          'dl_client_create');

  late final DLClientDestroyDart dlClientDestroy =
      _lib.lookupFunction<DLClientDestroyNative, DLClientDestroyDart>(
          'dl_client_destroy');

  late final DLClientInitializeDart dlClientInitialize =
      _lib.lookupFunction<DLClientInitializeNative, DLClientInitializeDart>(
          'dl_client_initialize');

  late final DLClientSetProductPublicKeyDart dlClientSetProductPublicKey =
      _lib.lookupFunction<DLClientSetProductPublicKeyNative,
              DLClientSetProductPublicKeyDart>(
          'dl_client_set_product_public_key');

  late final DLClientImportTokenDart dlClientImportToken =
      _lib.lookupFunction<DLClientImportTokenNative, DLClientImportTokenDart>(
          'dl_client_import_token');

  late final DLClientOfflineVerifyDart dlClientOfflineVerify =
      _lib.lookupFunction<DLClientOfflineVerifyNative, DLClientOfflineVerifyDart>(
          'dl_client_offline_verify_current_token');

  late final DLClientGetStatusDart dlClientGetStatus =
      _lib.lookupFunction<DLClientGetStatusNative, DLClientGetStatusDart>(
          'dl_client_get_status');

  late final DLClientActivateBindDeviceDart dlClientActivateBindDevice =
      _lib.lookupFunction<DLClientActivateBindDeviceNative,
              DLClientActivateBindDeviceDart>(
          'dl_client_activate_bind_device');

  late final DLClientRecordUsageDart dlClientRecordUsage =
      _lib.lookupFunction<DLClientRecordUsageNative, DLClientRecordUsageDart>(
          'dl_client_record_usage');

  late final DLClientExportCurrentTokenEncryptedDart dlClientExportCurrentTokenEncrypted =
      _lib.lookupFunction<DLClientExportCurrentTokenEncryptedNative,
              DLClientExportCurrentTokenEncryptedDart>(
          'dl_client_export_current_token_encrypted');

  late final DLClientExportActivatedTokenEncryptedDart dlClientExportActivatedTokenEncrypted =
      _lib.lookupFunction<DLClientExportActivatedTokenEncryptedNative,
              DLClientExportActivatedTokenEncryptedDart>(
          'dl_client_export_activated_token_encrypted');

  late final DLClientExportStateChangedTokenEncryptedDart dlClientExportStateChangedTokenEncrypted =
      _lib.lookupFunction<DLClientExportStateChangedTokenEncryptedNative,
              DLClientExportStateChangedTokenEncryptedDart>(
          'dl_client_export_state_changed_token_encrypted');

  late final DLClientActivateDart dlClientActivate =
      _lib.lookupFunction<DLClientActivateNative, DLClientActivateDart>(
          'dl_client_activate');

  late final DLClientIsActivatedDart dlClientIsActivated =
      _lib.lookupFunction<DLClientIsActivatedNative, DLClientIsActivatedDart>(
          'dl_client_is_activated');

  late final DLClientGetDeviceIdDart dlClientGetDeviceId =
      _lib.lookupFunction<DLClientGetDeviceIdNative, DLClientGetDeviceIdDart>(
          'dl_client_get_device_id');

  late final DLClientGetDeviceStateDart dlClientGetDeviceState =
      _lib.lookupFunction<DLClientGetDeviceStateNative, DLClientGetDeviceStateDart>(
          'dl_client_get_device_state');

  late final DLClientShutdownDart dlClientShutdown =
      _lib.lookupFunction<DLClientShutdownNative, DLClientShutdownDart>(
          'dl_client_shutdown');

  late final DLClientGetStatePayloadDart dlClientGetStatePayload =
      _lib.lookupFunction<DLClientGetStatePayloadNative, DLClientGetStatePayloadDart>(
          'dl_client_get_state_payload');

  late final DLClientAddRecoveryChannelDart dlClientAddRecoveryChannel =
      _lib.lookupFunction<DLClientAddRecoveryChannelNative, DLClientAddRecoveryChannelDart>(
          'dl_client_add_recovery_channel');

  late final DLClientRemoveRecoveryChannelDart dlClientRemoveRecoveryChannel =
      _lib.lookupFunction<DLClientRemoveRecoveryChannelNative, DLClientRemoveRecoveryChannelDart>(
          'dl_client_remove_recovery_channel');

  late final DLClientGetCurrentTokenJsonDart dlClientGetCurrentTokenJson =
      _lib.lookupFunction<DLClientGetCurrentTokenJsonNative, DLClientGetCurrentTokenJsonDart>(
          'dl_client_get_current_token_json');

  late final DLClientActivateWithTokenDart dlClientActivateWithToken =
      _lib.lookupFunction<DLClientActivateWithTokenNative, DLClientActivateWithTokenDart>(
          'dl_client_activate_with_token');
}
