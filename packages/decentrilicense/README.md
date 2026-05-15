# DecentriLicense Flutter/Dart SDK

Dart FFI bindings for the DecentriLicense `dl-core` native library.

## Features

- Token import (encrypted / JSON)
- Offline verification (trust chain + signature)
- Device activation & binding
- Usage recording / state migration
- Token export (encrypted)
- Full validation wizard CLI

## Prerequisites

- Dart SDK >= 3.0.0
- `libdecentrilicense` shared library (built from `dl-core`)

## Quick Start

### 1. Build dl-core

```bash
cd dl-core
mkdir build && cd build
cmake .. && cmake --build .
```

### 2. Set library path

```bash
# macOS
export DYLD_LIBRARY_PATH=/path/to/dl-core/build:$DYLD_LIBRARY_PATH

# Linux
export LD_LIBRARY_PATH=/path/to/dl-core/build:$LD_LIBRARY_PATH
```

### 3. Run validation wizard

```bash
cd sdks/flutter
dart pub get
dart run bin/validation_wizard.dart
```

### 4. Quick validate (non-interactive)

```bash
dart run bin/validation_wizard.dart validate <token_file> <product_public_key_file>
```

## Programmatic Usage

```dart
import 'package:decentrilicense/decentrilicense.dart';

void main() {
  final client = DecentriLicenseClient();
  
  client.initialize(udpPort: 13325, tcpPort: 23325);
  client.setProductPublicKey(productKeyPem);
  client.importToken(tokenString);
  
  final result = client.offlineVerifyCurrentToken();
  if (result.valid) {
    print('✅ Token is valid');
    final status = client.getStatus();
    print('Token ID: ${status.tokenId}');
  }
  
  client.shutdown();
}
```

## Custom Library Path

```dart
final client = DecentriLicenseClient(libraryPath: '/custom/path/libdecentrilicense.so');
```

## Architecture

```
Flutter/Dart App
       │
  DecentriLicenseClient (Dart wrapper)
       │
  FFI Bindings (ffi_bindings.dart)
       │
  libdecentrilicense (dl-core C API)
```

All cryptographic verification is performed by `dl-core` — no pure Dart crypto logic.
