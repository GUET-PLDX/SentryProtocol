# SentryProtocol

哨兵裁判系统决策发送模块。

- 通过 `referee_sentry_tp_name` 订阅 `Referee::RobotGameRefereePack`
- 在线且机器人状态新鲜、`remain_hp == 0` 时，在 `OnMonitor()` 中持续提交确认复活；存活或过期后撤销
- 通过 SharedTopic 指令 Topic 合并哨兵决策意图，由 Referee 原线程异步发送
- 通过 `SetSwitchMode()` 提交 1/2/3 三种基础姿态，结果由裁判 `0x020D` 确认
- `GetLastRequestError()` 与 `GetRejectedRequests()` 提供请求诊断，购买基线未建立、计数越界和非法姿态均可观察

## Required Hardware
None

## Constructor Arguments
- `referee`: `Referee*`
- `referee_sentry_tp_name`: 裁判系统摘要 topic，默认建议使用 `sentry_ref`
- `buy_bullet_topic_name`: 自主兑换允许发弹量 topic
- `remote_buy_bullet_times_topic_name`: 远程兑换发弹量次数 topic
- `remote_buy_hp_times_topic_name`: 远程兑换血量次数 topic
- `buy_resurrection_topic_name`: 兑换立即复活 topic
- `state_topic_name`: 切换姿态 topic

## DualBoard Topic Semantics

DualBoard is the producer of the decision topics. The payload semantics are
fixed as follows:

- `buy_bullet_topic_name` publishes a `uint16_t` bullet delta, which is passed
  to `Referee::AddNeedBullet`.
- Nonzero `uint8_t` values on each remote-buy topic cause one request: bullet
  uses `Referee::RequestRemoteBulletExchange`, and HP uses
  `Referee::SetHPRemote`.
- `buy_resurrection_topic_name` publishes a `bool` level, including `false`,
  to `Referee::SetRevivalRemote`.
- `state_topic_name` publishes a `uint8_t` state level. Only `1`, `2`, and `3`
  are admitted by `SetSwitchMode`; `0` and `4`–`6` do not overwrite the last
  valid stance. The initial stance is `3`.

Referee establishes purchase counters from the first valid `0x020D` feedback.
Before that baseline, purchase requests return `STATE_ERR`. Remote requests
advance by one only after the previous increment is confirmed by fresh feedback;
UART completion does not confirm a purchase. Limits are 2047 cumulative bullets
and 15 remote requests per category, with no wraparound. Topic callbacks and
`OnMonitor()` do not wait for UART transmission or bypass its shared limiter.

## Template Arguments
None

## Depends
- GUET-PLDX/Referee

## LibXR 2.0 静态装配

使用 xrobot 1.0.1 的 `module` / 有序 `args`；构造函数显式注入外设与服务，实例按依赖顺序创建。参数名和顺序以头文件中的构造函数为准，固件示例见 `User/RobotConfig/`。

保留 PLDX 控制、协议、超时与离线保护。 `OnMonitor()` 由生成的监控循环直接调用。
