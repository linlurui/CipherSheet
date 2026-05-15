# 原生库目录

按平台/架构存放 `libdecentrilicense` 动态库，由打包脚本嵌入到对应平台的 Flutter 应用包内。

## 目录结构

```
native/
  macos-arm64/        libdecentrilicense.dylib
  macos-x86_64/       libdecentrilicense.dylib, libssl.3.dylib, libcrypto.3.dylib
  linux-x86_64/       libdecentrilicense.so
  windows-x86_64/     libdecentrilicense.dll
```

## 同步最新构建产物

```bash
./scripts/sync_native_libs.sh
# 或指定源目录：
DL_CORE_BUILD_DIR=/path/to/build-all ./scripts/sync_native_libs.sh
```

## 平台打包

| 平台 | 命令 | 产物位置 |
|------|------|----------|
| macOS arm64 | `./scripts/build_macos.sh arm64` | `build/macos/.../Release/ciphersheet.app` |
| macOS x86_64 | `./scripts/build_macos.sh x86_64` | 同上 |
| Linux x86_64 | `./scripts/build_linux.sh` | `build/linux/x64/release/bundle/` |
| Windows x86_64 | `./scripts/build_windows.sh` （需 Windows 主机） | `build/windows/x64/runner/Release/` |

## 已知问题

- **macOS arm64 dylib 依赖 `/opt/homebrew/opt/openssl@3/`**：当前 arm64 构建链接的是 Homebrew OpenSSL 的绝对路径。打包脚本会尝试用 `install_name_tool` 把依赖改写到 `@executable_path/`，但 arm64 包目录下当前**没有**配套的 `libssl.3 / libcrypto.3` dylib（仅 x86_64 包带了）。
  - **临时方案**：在发布机器上确保已安装 `brew install openssl@3`，或手动把 `/opt/homebrew/opt/openssl@3/lib/lib{ssl,crypto}.3.dylib` 复制到 `native/macos-arm64/`，再次运行 `build_macos.sh arm64`。
  - **根本方案**：让 `dl-core` 在 arm64 上以静态链接或 `@rpath` 方式构建 OpenSSL（参考 x86_64 配置）。
- **Windows 加载名**：Dart FFI 在 Windows 加载 `decentrilicense.dll`（无 `lib` 前缀）。打包脚本会同时输出两个名字的副本兜底。
