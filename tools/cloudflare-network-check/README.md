# Cloudflare 只读连通性探针

用于先验证手机移动数据能否通过一个独立入口连接 Supabase。只读版本已部署并在手机移动数据下验证；当前不能直接将 APP 的 SUPABASE_URL 改为这个探针地址，因为业务接口尚未启用。

仅开放 `GET /health`，固定读取项目 `/auth/v1/health`；不接收或转发登录、数据库查询、API Key、Token 或密码。不需要配置 Supabase 服务端密钥。健康接口返回 401 是未携带密钥时的预期响应，只表示已收到 HTTP 响应。

本地验证（Node.js 18+）：

```bash
cd /Users/guochenyuan/Desktop/高佳欣/tools/cloudflare-network-check
npm test
```

只读版本有 5 项本地测试，业务候选版本有 12 项本地测试，合计 17 项通过；两个版本的 `wrangler@4.149.0 deploy --dry-run` 打包检查通过。dry-run 不上传或创建线上服务，不能替代真实账号回归。

用户已完成 Cloudflare 授权，且明确批准新增检测子域名。当前 `wrangler.jsonc` 指向只读代码 `src/index.js`，只绑定已批准的完整主机名，不配置根域名或通配符。更新前后均需检查该主机名仍绑定同一个 Worker；本次首次绑定使用官方 Domains API 的 `zone_name` 参数，未修改现有网站记录。

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

业务候选代码是 `src/gateway.js`，其配置 `wrangler.gateway.candidate.jsonc` 尚未部署。接入范围、凭据流向、客户端会话兼容和回退见 [业务入口接入评审](../../docs/业务入口接入评审-2026-10-13.md)。启用前必须取得超出“仅检测”范围的授权，再进行真实账号和业务回归。

## 实际部署与移动数据验证

只读探针已部署到 `gaojiaxin-network-check.rzyydsnw918zgnb.workers.dev`。该默认域名在手机移动数据下解析到与 Cloudflare DoH 不一致的地址并连接失败，不能据此切换 APP 服务地址。

用户已有 `pet-food-advisor.asia`，其现有网站仍有其他产品使用。仅新增已批准的 `gaojiaxin-check.pet-food-advisor.asia`，绑定同一个只读探针，没有绑定根域名、现有网站主机名或通配符路由。绑定后的根域名 A 记录和名称服务器与操作前一致。

2026-10-13，NOH AN01 默认网络 CELLULAR 下访问 [检测入口](https://gaojiaxin-check.pet-food-advisor.asia/health)：HTTP 200，约 1797 ms，返回 `gatewayReached: true, upstreamReached: true, upstreamStatus: 401`。电脑分别使用 Dart、curl 和浏览器请求标识也返回相同成功诊断；较早一次默认 Python 请求出现 403，原因未确定，因此不能推断所有请求环境都已验证。

新子域名和现有域名注册共用，无需额外购买域名。本次未升级 Supabase 套餐、未改 APP 服务地址、未重新发布 APK；检测成功不等于已经修复 APP 登录。

部署参考：[Cloudflare Wrangler 文档](https://developers.cloudflare.com/workers/wrangler/commands/)、[Workers Fetch API](https://developers.cloudflare.com/workers/runtime-apis/fetch/)。
