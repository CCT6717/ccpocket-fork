# ccpocket 重连重复会话 + 设置页自动滚动 修复设计

**日期**：2026-06-27
**范围**：3 个文件，~40 行改动
**风险**：中（WebSocket 连接生命周期 + BLoC 状态订阅）

---

## Bug 1：重连时会话重复创建

### 现象

用户打开 2 个对话，bridge 断线重连后出现 10+ 个会话，电脑差点卡死。

### Root Cause

三个缺陷叠加导致消息雪崩：

1. **过早设 connected**（`bridge_service.dart:391`）：`WebSocketChannel.connect()` 返回后立即设 `state = connected`，但此时 WebSocket 握手尚未完成。UI 层监听到 connected 后立即触发 `refresh()`→`send()`→sink.add 抛异常→消息入队→`_scheduleReconnect()`，形成循环。
2. **重复定时器**（`bridge_service.dart:892`）：`_scheduleReconnect()` 未取消已有 `_reconnectTimer`，`onError`+`onDone`+`send().catch` 三个入口可能同时创建多个定时器。
3. **竞态窗口**（`session_list_screen.dart:778-863`）：`send(start)` 在第 778 行，`_pendingNavigation = true` 在第 863 行。如果 `session_created` 在窗口期到达，会导致双重导航。

### 修复方案（方案 A：最小改动）

#### Change 1.1：延迟 connected 状态

**文件**：`bridge_service.dart`，`connect()` 方法（第 388-397 行）

- 删除第 391 行 `_setBridgeConnectionState(BridgeConnectionState.connected)`
- 将 `_lastConnectedAt`、`_reconnectAttempt = 0`、`_startPingTimer()`、`send(ClientMessage.clientCapabilities())`、`_flushMessageQueue()` 全部移到 `_channel!.stream.listen` 的 `onData` 回调中
- 用一个 `_handshakeCompleted` bool 标记防止 onData 多次触发初始化逻辑

**消息安全**：`connect()` 返回后 state 仍为 `connecting`，UI 层 `send()` 走 `_queueOfflineMessage()` 路径（第 922-923 行），消息安全入队。`onData` 触发后 `_flushMessageQueue()` 一次性发出。比原实现更安全。

```dart
// bridge_service.dart connect() 核心改动
_channel = WebSocketChannel.connect(Uri.parse(url));
// 不再立即设 connected，等 onData 确认握手完成
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
  // onError / onDone 不变，但在重置时加 _handshakeCompleted = false
```

需要在 `connect()` 开头加 `_handshakeCompleted = false`。

#### Change 1.2：防重复定时器

**文件**：`bridge_service.dart`，`_scheduleReconnect()` 方法（第 892 行）

在方法开头加一行：
```dart
_reconnectTimer?.cancel();
```

#### Change 1.3：竞态防护

**文件**：`session_list_screen.dart`，`_startNewSession()` 方法（第 765 行）

将 `_pendingNavigation = true` 从第 863 行移到第 778 行 `bridge.send()` 之前。

---

## Bug 2：设置页面自动滚动

### 现象

设置页面不碰屏幕也自己上下跳动，周期约 30 秒。

### Root Cause

两个缺陷叠加：

1. **全量 rebuild**（`settings_screen.dart:239`）：`BlocBuilder<SettingsCubit>` 内部 `context.watch<MachineManagerCubit>()`，MachineManagerCubit 每 30 秒健康检查 emit 新状态（`lastChecked` 更新）→ 整个 ListView 全量重建。
2. **focus 无限重试**（`settings_screen.dart:80-149`）：`_maybeFocusSupportSection` / `_maybeFocusConnectionSection` 在 targetContext==null 时重置守卫为 false，下次重建再次触发。配合 30 秒重建，形成无限循环。`_maybeFocusSupportSection` 还包含 `jumpTo(maxScrollExtent)` 强跳（第 117 行），即使后续 ensureVisible 失败，页面已经跳到底部。

### 修复方案（方案 D：精确订阅 + 守卫限次）

#### Change 2.1：context.select 精约订阅

**文件**：`settings_screen.dart`，BlocBuilder builder（第 239-243 行）

**最终方案**：用 Dart 3 record 精确提取只关心的字段，彻底过滤掉 `lastChecked` 等高频噪声。

将：
```dart
final machineManagerCubit = context.watch<MachineManagerCubit>();
final machineWithStatus = _activeMachineWithStatus(
  machineManagerCubit.state,
  state.activeMachineId,
);
```

改为：
```dart
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
```

- `Machine` 是 `@freezed`（值比较），`bool` 是原生比较
- 30 秒 `lastChecked` 更新不影响 `machine` 和 `online` → 不触发 rebuild

**下游适配**：builder 内原引用 `machineWithStatus?.machine` → `machineSnapshot?.machine`，`machineWithStatus?.status == MachineStatus.online` → `machineSnapshot?.online == true`。涉及行约 255-300，逐行替换即可。`_activeMachineWithStatus` 方法保留不删（其他地方可能调用）。

#### Change 2.2：守卫限次 + 删 jumpTo

**文件**：`settings_screen.dart`，`_maybeFocusConnectionSection()` 和 `_maybeFocusSupportSection()`

**_maybeFocusConnectionSection（第 80-109 行）**：
- `_didHandleConnectionFocus` 从 `bool` 改为 `int _focusConnectionRetries = 0`
- 判断条件改为 `_focusConnectionRetries >= 3`
- 每次进入 +1
- targetContext 为 null 时直接 return，不再重置计数器

**_maybeFocusSupportSection（第 111-149 行）**：
- 同样改为计数器 `_focusSupportRetries`，上限 3
- **删除第 115-118 行的 `jumpTo(maxScrollExtent)` 强跳逻辑**（最大元凶）
- targetContext 为 null 时直接 return

---

## 不改的部分

- **服务端去重**：客户端修复后不会重复发送 start 消息，服务端无需改动
- **WebSocket 握手验证**：不引入 `_channel!.ready` await（增加复杂度），用 onData 首次回调替代
- **设置页异步内容**：`_SpreadAppealMessage`、`_VersionTile` 等异步加载导致的高度变化在 30 秒 rebuild 消除后影响大幅降低，暂不处理

## 测试策略

1. **手动测试 Bug 1**：打开 2 个会话 → 断开 bridge（如关 WiFi）→ 等 5 秒 → 恢复 → 确认会话数不变
2. **手动测试 Bug 2**：打开设置页 → 不碰屏幕 → 观察 60 秒 → 确认页面不跳动
3. **回归**：正常新建会话、重连、设置页修改机器配置，确认功能正常

## 回滚策略

两组修改独立，可单独 revert 任一组。最坏情况：revert 后回到原状态（重连重复 + 设置跳动），无数据丢失风险。
