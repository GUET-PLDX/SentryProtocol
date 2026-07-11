# SentryProtocol

哨兵裁判系统决策发送模块。

- 通过 `referee_sentry_tp_name` 订阅 `Referee::RobotGameRefereePack`
- 检测到 `remain_hp == 0` 后，在 `OnMonitor()` 中持续调用 `Referee` 发送确认复活
- 通过 SharedTopic 指令 Topic 覆盖哨兵决策变量，并立即发送哨兵决策包
- 通过 `SetSwitchMode()` 可在本地直接切换姿态

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

## Template Arguments
None

## Depends
- qdu-future/Referee
