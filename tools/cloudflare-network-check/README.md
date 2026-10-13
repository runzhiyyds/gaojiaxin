# Cloudflare 只读连通性探针

用于先验证手机移动数据能否通过一个独立入口连接 Supabase。当前尚未部署，不能直接将 APP 的 SUPABASE_URL 改为这个探针地址。

仅开放 `GET /health`，固定读取项目 `/auth/v1/health`；不接收或转发登录、数据库查询、API Key、Token 或密码。不需要配置 Supabase 服务端密钥。健康接口返回 401 是未携带密钥时的预期响应，只表示已收到 HTTP 响应。

本地验证（Node.js 18+）：

```bash
cd /Users/guochenyuan/Desktop/高佳欣/tools/cloudflare-network-check
npm test
```

本次已通过 5 项本地测试，以及 `wrangler@4.149.0 deploy --dry-run` 打包检查；dry-run 不上传或创建线上服务。

部署前需要连接用户自己的 Cloudflare 账号并确认目标账户。可以在 Workers 控制台创建 `gaojiaxin-network-check`，粘贴 `src/index.js`；或在已授权的 Wrangler 环境使用此目录的 `wrangler.jsonc` 部署。部署操作会创建公开 HTTPS 入口，须使用用户确认的账户；不要求升级付费套餐。

部署后，用手机移动数据访问实际返回的 Worker URL 加 `/health`：

- 无法连接 Worker：新入口本身仍不可达，继续验证自有域名/其他入口；不要切换 APP。
- `upstreamReached: false`：已到达 Worker，但 Worker 到 Supabase 连接失败；根据 reason 检查。
- `upstreamReached: true, upstreamStatus: 401`：两段连接均收到 HTTP 响应，可以继续准备业务网关与真实账号回归；这不代表已经验证登录或数据库查询。
- 若 upstreamStatus 是 5xx 等其他状态，先排查上游响应；探针不把任意 HTTP 响应等同于业务正常。

业务网关需要另外实现并验证原有 Supabase 鉴权、请求超时、写入不重试、Storage URL 和 Realtime WebSocket；本探针没有这些功能。

部署参考：[Cloudflare Wrangler 文档](https://developers.cloudflare.com/workers/wrangler/commands/)、[Workers Fetch API](https://developers.cloudflare.com/workers/runtime-apis/fetch/)。
