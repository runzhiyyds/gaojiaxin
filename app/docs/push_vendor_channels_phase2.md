## 厂商通道 / APNs 双通道路线（第二/三期）

- **Android 厂商通道**
  - 根据设备品牌，接入对应 SDK（华为、小米、OPPO、vivo 等），仅在无 Google Play 服务或 FCM 不可用场景启用。
  - 在 `push_devices` 中扩展字段：`vendor_type`（huawei/xiaomi/oppo/vivo）、`vendor_token`。
  - Edge Function 根据 `platform + vendor_type` 选择推送方式：
    - 优先 FCM，其次对应厂商通道；
    - 厂商 SDK 由移动端获取 `vendor_token` 后上报，与当前表结构兼容。

- **iOS APNs 直连**
  - 在 Edge Function 中增加 APNs 客户端逻辑，使用 Token-based 身份验证（p8 证书）。
  - 客户端上报 `apns_token` 到 `push_devices` 新增字段中，后端根据 `platform = ios` 时优先走 APNs。
  - 长期方向：抽象“推送网关接口”，FCM / APNs / 厂商通道作为不同实现，按优先级和可用性动态选择。

