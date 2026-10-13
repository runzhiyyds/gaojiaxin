# Cloudflare 业务入口与连通性检测

2026-10-13，用户明确授权升级为业务入口并接入 APP 真机验证后，`https://gaojiaxin-check.pet-food-advisor.asia` 已启用业务转发。APP 本地配置已经切换，仍使用原 Supabase 项目的客户端公开密钥与持久会话键。

`GET /health` 继续固定读取原项目 `/auth/v1/health`，健康检测不转发客户端凭据；401 是未携带密钥时的预期健康响应。业务路径允许 Auth、REST/RPC、Storage、Realtime，固定原项目上游，转发客户端公开密钥、用户 JWT 与登录请求；没有服务端密钥或请求日志。鉴权与 RLS 仍由 Supabase 执行。

本地验证（Node.js 18+）：

```bash
cd /Users/guochenyuan/Desktop/高佳欣/tools/cloudflare-network-check
npm test
```

只读检测 5 项、业务入口 12 项本地测试，合计 17 项通过。手机移动数据下两个业务集成用例通过，覆盖旧会话、主要页面、密码登录、刷新、Realtime 订阅和重连。详细结果与限制见 [接入与验证记录](../../docs/业务入口接入评审-2026-10-13.md)。

当前 `wrangler.jsonc` 指向业务代码 `src/gateway.js`，`wrangler.readonly.jsonc` 保留只读回退代码 `src/index.js`。只绑定已批准的完整主机名，不配置根域名或通配符。首次绑定使用 Domains API 的 `zone_name`；本次升级使用 Scripts API 上传打包模块，升级前后核对该主机名绑定一致，未修改 DNS/路由。

Wrangler 授权需包含实际脚本管理权限（冒号与后缀需要完整保留）：

```bash
npx --yes wrangler@4.149.0 login --scopes 'account:read' 'user:read' 'workers_scripts:write'
```

`workers:write` 在本次账户实测中只能读取脚本清单，部署/子域名接口返回 403；`workers_scripts:write` 对应脚本、子域名和触发器的管理权限。浏览器确认后才获得授权。

部署后，用手机移动数据访问实际返回的 Worker URL 加 `/health`：

- 无法连接 Worker：新入口本身仍不可达，继续验证自有域名/其他入口；不要切换 APP。
- `upstreamReached: false`：已到达 Worker，但 Worker 到 Supabase 连接失败；根据 reason 检查。
- `upstreamReached: true, upstreamStatus: 401`：两段连接均收到 HTTP 响应，可以继续准备业务网关与真实账号回归；这不代表已经验证登录或数据库查询。
- 若 upstreamStatus 是 5xx 等其他状态，先排查上游响应；探针不把任意 HTTP 响应等同于业务正常。

打包检查使用 `npx --yes wrangler@4.149.0 deploy --dry-run`；只读回退配置可追加 `--config wrangler.readonly.jsonc`。它们仅检查打包，不发布。当前 OAuth 可执行 Scripts API 上传，但 Wrangler 自动管理 custom domain 可能还需要区域读取权限；遇到区域查询失败应核对权限，不能扩大到根域名或修改其他产品记录。

## 实际部署与移动数据验证

最初部署的默认地址 `gaojiaxin-network-check.rzyydsnw918zgnb.workers.dev` 在手机移动数据下解析到与 Cloudflare DoH 不一致的地址并连接失败；APP 使用已验证的自有子域名。

用户已有 `pet-food-advisor.asia`，其现有网站仍有其他产品使用。仅新增已批准的 `gaojiaxin-check.pet-food-advisor.asia`，绑定同一个只读探针，没有绑定根域名、现有网站主机名或通配符路由。绑定后的根域名 A 记录和名称服务器与操作前一致。

2026-10-13，NOH AN01 默认网络 CELLULAR 下访问 [检测入口](https://gaojiaxin-check.pet-food-advisor.asia/health)：HTTP 200，约 1797 ms，返回 `gatewayReached: true, upstreamReached: true, upstreamStatus: 401`。电脑分别使用 Dart、curl 和浏览器请求标识也返回相同成功诊断；较早一次默认 Python 请求出现 403，原因未确定，因此不能推断所有请求环境都已验证。

新子域名和现有域名注册共用，无需额外购买域名，也未升级 Supabase 套餐。业务授权后已切换本地 APP 并安装验证 Release 包；尚未替换蒲公英线上下载包。

部署参考：[Cloudflare Wrangler 文档](https://developers.cloudflare.com/workers/wrangler/commands/)、[Workers Fetch API](https://developers.cloudflare.com/workers/runtime-apis/fetch/)、[模块上传 API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/)。
