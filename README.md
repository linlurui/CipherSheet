# CipherSheet

基于 [DecentriLicense](https://github.com/linlurui/decentri-license) **状态链 (State Chain)** 的跨平台加密账本应用。
所有账本变更都会被签名写入授权 Token 的 `state_payload`，账本 = 软件授权 = 资产，激活即恢复。

> **支持平台**：macOS / Windows / Linux (PC)、iOS / Android (移动端)。
> **技术栈**：Flutter 3.x · Provider · `dl-core` FFI · AES-256-GCM · PBKDF2 · fl_chart。

---

## 功能概览

- **激活 / 跨设备恢复**：粘贴 / 读取由 dl-issuer 签发的离线 token 即可激活；二次激活会自动从 `state_payload` 还原账本元数据。
- **多账本**：每个账本独立利率、独立预警限额，共用一个全局助记词。
- **三层模型**：Ledger → Bill (表格) → Cell (格子)，每个 Bill 是同类型格子的容器，Cell 是最小记账单元。
- **宫格展示**：Bill 以 Tab 切换，Cell 按截图风格 Grid 排列，倍率分色，序号自动 `01,02,...`。
- **批量生成**：支持批量生成 Bill (表格) 或 Cell (格子)。
- **格子详情**：点击格子进入详情页，查看记账记录列表、参数管理、公式设置。
- **动态参数 & 公式**：每个 Cell 可自定义参数（如利率、倍率等）和计算公式，公式引擎支持变量替换 + 四则运算。
- **动态利率**：设置图标弹窗实时调整利率 & 预警限额比例，立即生效并上链。
- **结算 / 盘点**：填入实结金额，按当前利率算 expected/diff，盘盈/盘亏，配 `fl_chart` 柱状图。盘点记录 Tab 展示历史结算列表。
- **激活后助记词向导**：首次激活后引导用户设置全局助记词，增强安全性。
- **全局助记词（双模式）**：8 词点选（随机生成）或 16 位手输密码（含特殊符号），PBKDF2 → AES-256-GCM 二次加密所有账本金额字段；同时注册为 DL recovery channel（包裹 SEK），方便新设备恢复。
- **本地加密落盘**：账单明细以 device 主密钥 AES-GCM 加密落入 `<appSupportDir>/ciphersheet/store.aesgcm`；Token 仅保留摘要 (hash + 元数据)，避免 token 体积膨胀和验签变慢。
- **自动 token 备份**：每次写入后自动导出最新 token 至 `<appSupportDir>/ciphersheet/token_latest.txt`（只保留一份，覆盖写入）。

---

## 架构

```
Flutter UI (Material 3)
        │
   AppState (ChangeNotifier)
   ├── LicenseService → DecentriLicenseClient(FFI) → libdecentrilicense.dylib/so/dll
   ├── LocalStore (AES-GCM 加密的 JSON, device key)
   └── PassphraseCrypto (PBKDF2 + AES-GCM, 助记词二次加密)
```

数据分层：

| 层 | 存储介质 | 内容 |
|---|---|---|
| state_payload (上链) | DecentriLicense Token | 账本元数据 + Bill 摘要 + Cell 摘要 (hash + index + title) + 最新结算 |
| 本地加密文件 | `<appSupport>/ciphersheet/store.aesgcm` | Bill/Cell 完整明细 / 历史结算（Cell 金额可被助记词二次加密） |
| 内存 | RAM | 全局助记词明文（解锁后存于内存，不持久化） |

---

## 目录结构

```
lib/
  main.dart                                 # 入口
  app.dart                                  # MaterialApp + 引导
  theme.dart                                # 主题 + 倍率配色
  core/
    crypto/passphrase_crypto.dart           # 助记词派生 + AES-GCM
    license/license_service.dart            # DL SDK 封装 + 多路径 dylib 搜索
    storage/local_store.dart                # 设备级 AES-GCM 持久化
  models/
    ledger.dart                             # Ledger + LedgerView (三层聚合)
    bill.dart                               # Bill (表格容器，含 Cells)
    cell.dart                               # Cell + CellRecord + CellParameter
    settlement.dart                         # Settlement (含 cell 快照)
    state_chain_payload.dart                # 上链 payload + 本地存储 schema
  state/
    app_state.dart                          # 业务缝合 + 状态机
  features/
    activation/activation_screen.dart       # 激活页
    activation/mnemonic_wizard_screen.dart  # 激活后助记词向导
    ledgers/ledgers_screen.dart             # 账本列表
    ledger_detail/                          # 账本详情
      ledger_detail_screen.dart             # Bill Tab + Cell 宫格 + 工具栏
      widgets/
        bill_cell.dart                      # 格子组件 (Cell)
        cell_detail_screen.dart             # 格子详情 (记录/参数/公式)
        batch_generate_dialog.dart          # 一键批量
        settings_dialog.dart                # 动态利率/限额比例
        mnemonic_dialog.dart                # 设置/解锁助记词
    settlement/settlement_screen.dart       # 结算 + 盘点记录 + 图表
assets/keys/                                # 放 product_public_key.pem
```

---

## 开发启动注意事项

### 1. Flutter SDK 不在 PATH

本机 Flutter 安装在 `/Users/rocky/flutter/bin/`，但默认未加入 shell PATH，导致终端和 IDE 找不到 `flutter`/`dart` 命令。

**永久修复**（推荐）：

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**临时使用**（每次终端 session）：

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter run -d macos
```

> 当前版本：Flutter 3.41.4 · Dart 3.11.1 · DevTools 2.54.1

### 2. dl-core 动态库

macOS 调试时，`libdecentrilicense.dylib` 必须能被应用找到。`LicenseService` 会按以下顺序搜索：

1. `@executable_path/libdecentrilicense.dylib`（打包后，Xcode Build Phase 自动拷贝）
2. 开发期绝对路径兜底：`/Volumes/workspace/project/ccait/dl-issuer/sdks/flutter/lib/native/`

**dylib install_name 必须设置**：

```bash
install_name_tool -id "@executable_path/libdecentrilicense.dylib" \
  /path/to/libdecentrilicense.dylib
```

否则 macOS dyld 无法在 app bundle 内找到它。

### 3. macOS 沙盒已禁用

Debug 配置 `macos/Runner/DebugProfile.entitlements` 中 `app-sandbox = false`，这是为了让 dylib 能访问 `/opt/homebrew` 下的 OpenSSL/curl。发布时需重新评估沙盒策略。

### 4. 产品公钥

`assets/keys/product_public_key.pem` 必须包含 `ROOT_SIGNATURE:` 段（由 dl-issuer 生成），否则激活验签失败。

### 5. 激活流程注意

正确的激活调用链：

- **加密 Token**：`import_token()` → `activate_bind_device()`
- **JSON Token**：`import_token()` → `offline_verify_current_token()`

**不要**使用 `activateWithToken()`，该方法做了错误的 trust chain 验证。

### 6. 热重载 vs 热重启

- 涉及模型字段变更（如 `Cell` 新增 `settlementEvent`）时，**热重载不会生效**，必须完全热重启（`R` 键或停止后重新 `flutter run`）。
- 涉及 FFI dylib 变更时，也需要完全重启。
- 出现 Ticker 相关报错时，通常是热重载状态不一致导致，完全重启即可恢复。

### 7. flutter analyze

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /Volumes/workspace/project/CipherSheet
flutter analyze
```

当前项目会有少量 `info` 级别提示（`prefer_const_constructors`、`use_build_context_synchronously`），无 error / warning 可正常编译运行。

---

## 一次性准备

### 1. 编译 dl-core 动态库

```bash
cd /Volumes/workspace/project/ccait/dl-issuer/dl-core
mkdir -p build && cd build
cmake .. && cmake --build .
# 产物: build/libdecentrilicense.dylib (macOS) / .so / .dll
```

或复用已有产物：`sdks/flutter/lib/native/libdecentrilicense.dylib`，应用启动时会自动搜索这些路径。

### 2. 放入产品公钥

```bash
cp /path/to/product_public_key.pem \
   /Volumes/workspace/project/CipherSheet/assets/keys/product_public_key.pem
```

### 3. 补齐平台目录 (脚手架)

> 我没有提交 `android/ios/macos/windows/linux` 平台目录，按下面命令一次性补齐：

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /Volumes/workspace/project/CipherSheet
flutter create --org com.ciphersheet --project-name ciphersheet \
  --platforms=macos,windows,linux,ios,android .
flutter pub get
```

### 4. 让 macOS 桌面能找到 dylib

最简方案：把 `libdecentrilicense.dylib` 拷到运行时同目录：

```bash
cp /Volumes/workspace/project/ccait/dl-issuer/sdks/flutter/lib/native/libdecentrilicense.dylib \
   /Volumes/workspace/project/CipherSheet/macos/Runner/
```

并在 `macos/Runner/Runner.xcodeproj` 中将该文件加入 `Copy Bundle Resources`（或直接放到 `Frameworks/`）。开发期 `LicenseService` 也会兜底搜索 `/Volumes/workspace/project/ccait/dl-issuer/...` 绝对路径。

Linux：把 `.so` 放到与可执行同目录，或 `LD_LIBRARY_PATH`。
Windows：把 `decentrilicense.dll` 放到 `build/windows/runner/Debug/`。

---

## 运行

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /Volumes/workspace/project/CipherSheet
flutter run -d macos        # PC 端
# 或
flutter run -d windows
flutter run -d linux
flutter run -d ios
flutter run -d android
```

---

## 操作流程

1. 启动 → 看到激活页 → 粘贴 dl-issuer 签发的 encrypted token → 点 **激活**。
2. 自动跳转到账本列表 → **+** 新建账本（输入名字 + 初始利率）。
3. 首次激活后 → **助记词向导** 引导设置全局助记词（8 词点选 或 16 位密码，可跳过）
4. 进入账本：
   - **Tab 切换** 不同 Bill (表格)
   - **更多菜单** → 新增/批量生成 Bill 或 Cell
   - **点击格子** → 进入 Cell 详情页（记账记录、参数管理、公式设置）
   - **长按格子** → 删除
   - **⚙️ 设置** → 动态调整利率 (`%`)、预警限额比例、手动预警限额
   - **🔑 助记词** → 设置/解锁全局助记词（启用后所有账本金额字段二次加密 + 注册成 DL recovery channel）
   - **✅ 结算** → 填实结金额，看 盘盈/盘亏 + 柱状盘点图；切换 Tab 查看历史盘点记录
5. 每次写入都会：
   - 重写本地加密文件
   - 调用 `client.recordUsage(state_payload)` 将摘要写进 Token 状态链
   - 自动导出最新 token 到 `<appSupport>/ciphersheet/token_latest.txt`

---

## 与原始需求字段对照

| 需求关键词 | 实现位置 |
|---|---|
| 激活是基本授权 | `ActivationScreen` + `LicenseService.activateWithToken` |
| 激活后助记词向导 | `MnemonicWizardScreen` |
| 新增账本 | `AppState.createLedger` |
| 三层模型 | `Ledger` → `Bill` (表格容器) → `Cell` (格子) |
| 格子记录列表 | `CellDetailScreen` (记账记录 Tab) |
| 格子参数 & 公式 | `CellDetailScreen` (参数 Tab + 公式 Tab) |
| 记账时间 | `CellRecord.timestamp` |
| 默认 01/02 序号 | `AppState._defaultCellTitle` / `_defaultBillTitle` |
| 一键批量 | `BatchGenerateDialog` + `AppState.batchAddCells` / `batchAddBills` |
| 点格子继续记账 | `CellDetailScreen._addRecord` |
| 设置图标·动态利率 | `LedgerSettingsDialog` (利率 + 限额比例 + 手动覆盖) |
| 结算图标 + 实结金额 | `SettlementScreen` (结算 Tab) |
| 盘点记录列表 | `SettlementScreen` (盘点记录 Tab) |
| 盘点图表 | `_ChartView` (fl_chart 柱状图，按 Cell 金额) |
| 数据加密入状态链 | `AppState._persistAndChain` → `LicenseService.recordUsage` |
| 每笔单独记录表 | `Bill.toDigest()` + `Cell.toDigest()` 写入 `state_payload` |
| 二次激活恢复 | `AppState._restoreFromTokenIfNeeded` |
| 全局助记词 | `LocalLedgerStore.mnemonicVerifier` + `PassphraseCrypto` + `LicenseService.addRecoveryChannel` |
| 双模式输入 | 8 词点选 (`MnemonicWizardScreen`) 或 16 位密码 (`SetMnemonicDialog`/`UnlockMnemonicDialog`) |

---

## 安全说明

- **全局助记词** 不上传、不入 Token、不入本地存储（仅以 PBKDF2 校验哈希形式存于 `LocalLedgerStore`）；遗失即数据永久不可读。支持 8 词点选和 16 位密码两种输入方式。
- **device.key** 由 OS 文件权限保护 (600)；若需要更强保护，可改为 keychain / DPAPI / libsecret。
- **DL recovery channel** 在助记词设置时同步注册，便于在新设备激活后用助记词解开 SEK 并解密 `state_payload` 的敏感部分。

---

## 已知限制 / TODO

- iOS/Android 暂未自动打包 `dl-core` 静态/动态库——需要 podspec / NDK 接入（建议优先桌面端）。
- 大量格子 (> ~5k) 时 `state_payload` 仍可能膨胀，可在 `StateChainPayload.fromViews` 中改为只取最近 N 条摘要 + 全量哈希。
- 没有云同步：跨设备恢复完全依赖手动传输 token 文件。
- UI 国际化暂时只做中文。
- Cell 详情页的记录编辑目前仅支持新增和删除，暂不支持编辑已有记录的金额/备注。
