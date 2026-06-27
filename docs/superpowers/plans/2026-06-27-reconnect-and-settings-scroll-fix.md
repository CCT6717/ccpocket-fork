# 重连重复会话 + 设置页自动滚动 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复两个严重 bug — 重连时会话重复创建（2→10+）和设置页面自动跳动

**Architecture:** 3 处精确修复 WebSocket 连接生命周期 + 2 处修复 BLoC 状态订阅。不改架构，最小侵入。

**Tech Stack:** Flutter/Dart, WebSocket, flutter_bloc, Freezed, Dart 3 records

## Global Constraints

- Dart 3.12+（record 语法需要）
- flutter_bloc 已有 `context.select` / `context.watch` / `context.read`
- `Machine` 和 `MachineWithStatus` 均为 `@freezed` 类（值比较）
- 不改 bridge server 端代码

---

### Task 1: 延迟 connected 状态到首次 onData（bridge_service.dart）

**Files:**
- Modify: `apps/mobile/lib/services/bridge_service.dart:145` — 新增 `_handshakeCompleted` 字段
- Modify: `apps/mobile/lib/services/bridge_service.dart:370-436` — 重写 connect() 核心逻辑

**Interfaces:**
- Produces: `_handshakeCompleted` bool 标记，onData 首次回调触发 connected + flush
- Consumes: 无新依赖

- [ ] **Step 1: 添加 `_handshakeCompleted` 字段**

在 `_reconnectAttempt` 声明（第 145 行）附近添加：

```dart
  bool _handshakeCompleted = false;
```

- [ ] **Step 2: 重写 connect() 中的状态设定逻辑**

找到 `connect()` 方法中以下代码（第 388-397 行）：

```dart
      _channel = WebSocketChannel.connect(
        Uri.parse(url),
      );
      _setBridgeConnectionState(BridgeConnectionState.connected);
      _lastConnectedAt = DateTime.now();
      _reconnectAttempt = 0;
      // Start application-layer ping for RTT measurement
      _startPingTimer();
      send(ClientMessage.clientCapabilities());
      _flushMessageQueue();

      _channelSub = _channel!.stream.listen(
        (data) {
          if (epoch != _connectionEpoch) return;
          _incomingMessageQueue = _incomingMessageQueue
              .catchError((_) {})
              .then((_) => _handleIncomingMessage(data as String, epoch));
        },
```

替换为：

```dart
      _channel = WebSocketChannel.connect(
        Uri.parse(url),
      );
      _handshakeCompleted = false;
      _reconnectAttempt = 0;

      _channelSub = _channel!.stream.listen(
        (data) {
          if (epoch != _connectionEpoch) return;
          if (!_handshakeCompleted) {
            _handshakeCompleted = true;
            _setBridgeConnectionState(BridgeConnectionState.connected);
            _lastConnectedAt = DateTime.now();
            _startPingTimer();
            send(ClientMessage.clientCapabilities());
            _flushMessageQueue();
          }
          _incomingMessageQueue = _incomingMessageQueue
              .catchError((_) {})
              .then((_) => _handleIncomingMessage(data as String, epoch));
        },
```

- [ ] **Step 3: 在 onError 和 onDone 中重置 `_handshakeCompleted`**

找到 `onError` 回调（约第 406-415 行），在 `_setBridgeConnectionState(BridgeConnectionState.disconnected)` 之前加：

```dart
            _handshakeCompleted = false;
```

找到 `onDone` 回调（约第 417-427 行），在 `_channel = null` 之后加：

```dart
            _handshakeCompleted = false;
```

- [ ] **Step 4: 在 catch 块中也重置**

找到 connect() 的 catch 块（约第 430-435 行），在 `_setBridgeConnectionState(BridgeConnectionState.disconnected)` 之前加：

```dart
      _handshakeCompleted = false;
```

- [ ] **Step 5: Flutter analyze 验证**

Run: `cd D:\project\ccpocket\apps\mobile && flutter analyze lib/services/bridge_service.dart`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
cd D:\project\ccpocket
git add apps/mobile/lib/services/bridge_service.dart
git commit -m "fix: delay connected state until first WebSocket onData to prevent reconnect message avalanche"
```

---

### Task 2: 防重复重连定时器（bridge_service.dart）

**Files:**
- Modify: `apps/mobile/lib/services/bridge_service.dart:892` — _scheduleReconnect() 加 cancel

**Interfaces:**
- 依赖 Task 1 的 `_handshakeCompleted` 字段（独立可运行，但合并提交更干净）
- Produces: 无新接口

- [ ] **Step 1: 添加定时器取消**

找到 `_scheduleReconnect()` 方法（第 892 行），在方法体开头（`if (_intentionalDisconnect` 之前）添加：

```dart
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
```

完整方法变为：

```dart
  void _scheduleReconnect() {
    if (_intentionalDisconnect || _lastUrl == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _totalReconnectAttempts++;
    _reconnectAttempt++;
    // ...后续不变
```

- [ ] **Step 2: Flutter analyze 验证**

Run: `cd D:\project\ccpocket\apps\mobile && flutter analyze lib/services/bridge_service.dart`
Expected: No errors

- [ ] **Step 3: Commit（与 Task 1 合并为一个 commit）**

如果 Task 1 已 commit，这里 amend：

```bash
cd D:\project\ccpocket
git add apps/mobile/lib/services/bridge_service.dart
git commit --amend --no-edit
```

或单独 commit：

```bash
git commit -m "fix: cancel existing reconnect timer before scheduling new one"
```

---

### Task 3: 竞态防护 — _pendingNavigation 前移（session_list_screen.dart）

**Files:**
- Modify: `apps/mobile/lib/features/session_list/session_list_screen.dart:778,863` — 移动 _pendingNavigation 赋值

**Interfaces:**
- Consumes: `BridgeService.send()`, `_navigateToChat()`
- Produces: session_created 处理逻辑不变，只是时序安全

- [ ] **Step 1: 移动 `_pendingNavigation = true`**

找到 `_startNewSession()` 方法（第 765 行）。当前第 778 行是 `bridge.send(ClientMessage.start(...))`，第 863 行是 `_pendingNavigation = true`。

将第 863 行的 `_pendingNavigation = true;` **删除**，并在第 778 行 `bridge.send(` **之前**添加：

```dart
    _pendingNavigation = true;
```

即 `_startNewSession` 的关键部分变为：

```dart
  void _startNewSession(NewSessionParams result) {
    final bridge = context.read<BridgeService>();
    final settings = context.read<SettingsCubit>().state;
    final isOffline = !bridge.isConnected;
    // ... codex profile 逻辑 ...
    _pendingResumeProjectPath = result.projectPath;
    _pendingResumeGitBranch = result.worktreeBranch;
    _pendingNavigation = true;  // ← 移到这里，在 send 之前
    bridge.send(
      ClientMessage.start(
        // ... 参数不变 ...
      ),
    );
    if (isOffline) {
      // ...
      return;
    }
    if (_hasPendingStart(bridge, result)) {
      return;
    }
    // Navigate immediately to chat with pending state
    final pendingId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    // _pendingNavigation 已经在上面设为 true，删除原来的赋值
    _navigateToChat(
```

- [ ] **Step 2: Flutter analyze 验证**

Run: `cd D:\project\ccpocket\apps\mobile && flutter analyze lib/features/session_list/session_list_screen.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd D:\project\ccpocket
git add apps/mobile/lib/features/session_list/session_list_screen.dart
git commit -m "fix: set _pendingNavigation before send() to close race window with session_created"
```

---

### Task 4: context.select 精确订阅（settings_screen.dart）

**Files:**
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart:239-259` — 替换 context.watch 为 context.select + context.read

**Interfaces:**
- Produces: `machineSnapshot` 类型为 `({Machine? machine, bool online})?`
- Consumes: `MachineManagerCubit.state.machines`（列表）, `SettingsState.activeMachineId`

- [ ] **Step 1: 替换 context.watch 为 context.select + context.read**

找到 BlocBuilder builder 内的以下代码（第 239-259 行）：

```dart
          final machineManagerCubit = context.watch<MachineManagerCubit>();
          final machineWithStatus = _activeMachineWithStatus(
            machineManagerCubit.state,
            state.activeMachineId,
          );
          final enabledAgentsMode = enabledAgentsModeFromTabs(
            state.newSessionTabs,
          );
          final codexEnabled = isNewSessionTabEnabled(
            state.newSessionTabs,
            NewSessionTab.codex,
          );
          final claudeEnabled = isNewSessionTabEnabled(
            state.newSessionTabs,
            NewSessionTab.claude,
          );
          final machine = machineWithStatus?.machine;
          final isConnected = state.activeMachineId != null;
          final isUpdating =
              machine != null &&
              machineManagerCubit.state.updatingMachineId == machine.id;
```

替换为：

```dart
          final machineManagerCubit = context.read<MachineManagerCubit>();
          final activeMachineId = state.activeMachineId;
          final machineSnapshot = context.select<MachineManagerCubit, ({Machine? machine, bool online})?>(
            (cubit) {
              if (activeMachineId == null) return null;
              final item = cubit.state.machines
                  .where((m) => m.machine.id == activeMachineId)
                  .firstOrNull;
              if (item == null) return null;
              return (machine: item.machine, online: item.status == MachineStatus.online);
            },
          );
          final machineWithStatus = activeMachineId != null
              ? _activeMachineWithStatus(
                  machineManagerCubit.state,
                  activeMachineId,
                )
              : null;
          final enabledAgentsMode = enabledAgentsModeFromTabs(
            state.newSessionTabs,
          );
          final codexEnabled = isNewSessionTabEnabled(
            state.newSessionTabs,
            NewSessionTab.codex,
          );
          final claudeEnabled = isNewSessionTabEnabled(
            state.newSessionTabs,
            NewSessionTab.claude,
          );
          final machine = machineSnapshot?.machine;
          final isConnected = activeMachineId != null;
          final isUpdating =
              machine != null &&
              machineManagerCubit.state.updatingMachineId == machine.id;
```

**关键说明：**
- `context.read<MachineManagerCubit>()` 获取 cubit 引用但**不订阅**，用于后续读取 `updatingMachineId`、`latestBridgeVersion` 等不需响应式更新的字段
- `context.select` 只订阅 `machine` + `online` 变化，过滤掉 `lastChecked` 等 30 秒噪声
- `machineWithStatus` 保留用于传递给 `_BridgeUpdateStatusTile`（它需要 `versionInfo`），但通过 `context.read` 获取 cubit 后手动查询，而非 `context.watch`
- `machine` 变量改用 `machineSnapshot?.machine`（值比较），`isConnected` 用 `activeMachineId`
- `machineWithStatus` 是非响应式的一次性读取——仅在 SettingsCubit 触发 rebuild 时刷新，不再受 MachineManagerCubit 30 秒 emit 影响。bridge 版本信息的更新频率已足够（用户手动刷新或设置页打开时）

- [ ] **Step 2: Flutter analyze 验证**

Run: `cd D:\project\ccpocket\apps\mobile && flutter analyze lib/features/settings/settings_screen.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd D:\project\ccpocket
git add apps/mobile/lib/features/settings/settings_screen.dart
git commit -m "fix: replace context.watch with context.select in settings to stop 30s rebuild cycle"
```

---

### Task 5: focus 守卫限次 + 删 jumpTo（settings_screen.dart）

**Files:**
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart:67-78` — 字段声明
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart:80-149` — 两个 focus 方法

**Interfaces:**
- Consumes: `_connectionSectionKey`, `_supportSectionKey`（GlobalKey，不变）
- Produces: `_focusConnectionRetries`, `_focusSupportRetries`（int 计数器）

- [ ] **Step 1: 替换字段声明**

找到第 73-74 行：

```dart
  bool _didHandleConnectionFocus = false;
  bool _didHandleSupportFocus = false;
```

替换为：

```dart
  int _focusConnectionRetries = 0;
  int _focusSupportRetries = 0;
```

- [ ] **Step 2: 重写 `_maybeFocusConnectionSection`**

找到第 80-109 行的 `_maybeFocusConnectionSection()` 方法，替换为：

```dart
  void _maybeFocusConnectionSection() {
    if (!widget.focusConnection || _focusConnectionRetries >= 3) return;
    _focusConnectionRetries++;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final targetContext = _connectionSectionKey.currentContext;
      if (targetContext == null || !targetContext.mounted) {
        return; // 静默放弃，不再重置计数器
      }
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
      if (!mounted) return;

      setState(() {
        _highlightConnectionSection = true;
      });
      _connectionHighlightTimer?.cancel();
      _connectionHighlightTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        setState(() {
          _highlightConnectionSection = false;
        });
      });
    });
  }
```

- [ ] **Step 3: 重写 `_maybeFocusSupportSection`**

找到第 111-149 行的 `_maybeFocusSupportSection()` 方法，替换为：

```dart
  void _maybeFocusSupportSection() {
    if (!widget.focusSupport || _focusSupportRetries >= 3) return;
    _focusSupportRetries++;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ponytail: 删除 jumpTo(maxExtent) 强跳，它在 targetContext 为 null 时
      // 会无条件跳到底部，是自动滚动的最大元凶
      if (!mounted) return;
      final targetContext = _supportSectionKey.currentContext;
      if (targetContext == null || !targetContext.mounted) {
        return; // 静默放弃，不再重置计数器
      }
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
      if (!mounted) return;

      setState(() {
        _highlightSupportSection = true;
      });
      _supportHighlightTimer?.cancel();
      _supportHighlightTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        setState(() {
          _highlightSupportSection = false;
        });
      });
    });
  }
```

- [ ] **Step 4: Flutter analyze 验证**

Run: `cd D:\project\ccpocket\apps\mobile && flutter analyze lib/features/settings/settings_screen.dart`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
cd D:\project\ccpocket
git add apps/mobile/lib/features/settings/settings_screen.dart
git commit -m "fix: limit focus retry to 3 attempts and remove jumpTo(maxExtent) in settings"
```

---

### Task 6: 全量验证

**Files:** 无新增修改

- [ ] **Step 1: Flutter analyze 全量**

Run: `cd D:\project\ccpocket\apps\mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 2: 运行已有测试**

Run: `cd D:\project\ccpocket\apps\mobile && flutter test`
Expected: All tests pass

- [ ] **Step 3: 最终 commit（如有测试修复）**

```bash
cd D:\project\ccpocket
git add -A
git commit -m "test: update tests for reconnect and settings scroll fixes"
```

仅在测试需要适配时才 commit。如果全部绿灯则跳过此步。

- [ ] **Step 4: 推送到 fork**

```bash
cd D:\project\ccpocket
git push fork main
```
