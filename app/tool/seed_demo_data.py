import json
import random
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path


EMAIL_A = "123@163.com"
EMAIL_B = "test@163.com"
PASSWORD = "123456"
INVITE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


@dataclass
class UserCtx:
    base_url: str
    anon_key: str
    email: str
    access_token: str
    user_id: str

    @property
    def headers(self) -> dict[str, str]:
        return {
            "apikey": self.anon_key,
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
        }


def read_env() -> tuple[str, str]:
    env_path = Path("env.json")
    if not env_path.exists():
        raise RuntimeError("未找到 env.json")
    env = json.loads(env_path.read_text())
    url = env.get("SUPABASE_URL")
    anon_key = env.get("SUPABASE_ANON_KEY")
    if not url or not anon_key:
        raise RuntimeError("env.json 缺少 Supabase 配置")
    return url, anon_key


def request_json(
    method: str,
    url: str,
    headers: dict[str, str],
    body=None,
    allow_404: bool = False,
):
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="ignore")
        if allow_404 and e.code == 404:
            return None
        raise RuntimeError(f"{method} {url} 失败: {e.code} {raw}") from e


def auth_headers(anon_key: str) -> dict[str, str]:
    return {
        "apikey": anon_key,
        "Content-Type": "application/json",
    }


def sign_in(base_url: str, anon_key: str, email: str, password: str) -> UserCtx:
    url = f"{base_url}/auth/v1/token?grant_type=password"
    res = request_json(
        "POST",
        url,
        auth_headers(anon_key),
        {"email": email, "password": password},
    )
    token = res.get("access_token")
    user_id = ((res.get("user") or {}).get("id"))
    if not token or not user_id:
        raise RuntimeError(f"登录失败: {email}")
    print(f"登录成功: {email}")
    return UserCtx(base_url=base_url, anon_key=anon_key, email=email, access_token=token, user_id=user_id)


def rest_url(ctx: UserCtx, path: str, **query) -> str:
    qs = urllib.parse.urlencode(query, doseq=True)
    return f"{ctx.base_url}/rest/v1/{path}" + (f"?{qs}" if qs else "")


def select_rows(ctx: UserCtx, table: str, **query):
    url = rest_url(ctx, table, **query)
    return request_json("GET", url, {**ctx.headers, "Accept": "application/json"}) or []


def select_single(ctx: UserCtx, table: str, **query):
    rows = select_rows(ctx, table, **query)
    return rows[0] if rows else None


def insert_rows(ctx: UserCtx, table: str, rows):
    url = rest_url(ctx, table)
    return request_json(
        "POST",
        url,
        {**ctx.headers, "Prefer": "return=representation"},
        rows,
    )


def update_rows(ctx: UserCtx, table: str, body: dict, **query):
    url = rest_url(ctx, table, **query)
    return request_json(
        "PATCH",
        url,
        {**ctx.headers, "Prefer": "return=representation"},
        body,
    )


def delete_rows(ctx: UserCtx, table: str, **query):
    url = rest_url(ctx, table, **query)
    return request_json(
        "DELETE",
        url,
        {**ctx.headers, "Prefer": "return=representation"},
    )


def rpc(ctx: UserCtx, fn: str, body: dict):
    url = rest_url(ctx, f"rpc/{fn}")
    return request_json("POST", url, ctx.headers, body)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def profile(ctx: UserCtx, user_id: str):
    row = select_single(ctx, "profiles", select="*", id=f"eq.{user_id}")
    if not row:
        raise RuntimeError(f"未找到 profile: {user_id}")
    return row


def space(ctx: UserCtx, space_id: str):
    return select_single(ctx, "couple_spaces", select="*", id=f"eq.{space_id}")


def update_nickname(ctx: UserCtx, user_id: str, nickname: str):
    update_rows(
        ctx,
        "profiles",
        {"nickname": nickname, "updated_at": iso(datetime.now(timezone.utc))},
        id=f"eq.{user_id}",
    )


def generate_invite_code(ctx: UserCtx) -> str:
    while True:
        code = "".join(random.choice(INVITE_CHARS) for _ in range(6))
        existing = select_single(ctx, "profiles", select="id", invite_code=f"eq.{code}")
        if not existing:
            return code


def release_if_safe(ctx: UserCtx):
    p = profile(ctx, ctx.user_id)
    space_id = p.get("couple_space_id")
    if not space_id:
        return
    s = space(ctx, space_id)
    if not s:
        update_rows(
            ctx,
            "profiles",
            {"couple_space_id": None, "invite_code": None, "updated_at": iso(datetime.now(timezone.utc))},
            id=f"eq.{ctx.user_id}",
        )
        return
    user_a = s.get("user_a_id")
    user_b = s.get("user_b_id")
    partner_id = user_b if user_a == ctx.user_id else user_a
    if partner_id:
        raise RuntimeError(f"{ctx.email} 当前已在完整情侣空间中，脚本停止以避免误删真实数据。")
    update_rows(
        ctx,
        "profiles",
        {"couple_space_id": None, "invite_code": None, "updated_at": iso(datetime.now(timezone.utc))},
        id=f"eq.{ctx.user_id}",
    )


def ensure_couple_space(a: UserCtx, b: UserCtx) -> str:
    pa = profile(a, a.user_id)
    pb = profile(b, b.user_id)
    space_a = pa.get("couple_space_id")
    space_b = pb.get("couple_space_id")
    if space_a and space_a == space_b:
        s = space(a, space_a)
        ids = {s.get("user_a_id"), s.get("user_b_id")}
        if a.user_id in ids and b.user_id in ids:
            update_nickname(a, a.user_id, "演示账号")
            update_nickname(a, b.user_id, "情侣演示")
            return space_a

    release_if_safe(a)
    release_if_safe(b)

    code = generate_invite_code(a)
    created = insert_rows(a, "couple_spaces", {"user_a_id": a.user_id, "user_b_id": None})[0]
    space_id = created["id"]
    update_rows(
        a,
        "profiles",
        {
            "nickname": "演示账号",
            "couple_space_id": space_id,
            "invite_code": code,
            "updated_at": iso(datetime.now(timezone.utc)),
        },
        id=f"eq.{a.user_id}",
    )
    update_nickname(b, b.user_id, "情侣演示")
    joined = rpc(b, "join_by_invite_code", {"code_input": code})
    if not isinstance(joined, dict) or joined.get("success") is not True:
        raise RuntimeError(f"绑定演示账号失败: {joined}")
    return space_id


def reset_demo_data(ctx: UserCtx, space_id: str):
    delete_rows(ctx, "exchange_records", couple_space_id=f"eq.{space_id}")
    delete_rows(ctx, "mall_goods", couple_space_id=f"eq.{space_id}")
    delete_rows(ctx, "point_deposits", couple_space_id=f"eq.{space_id}")
    delete_rows(ctx, "user_deposit_defaults", couple_space_id=f"eq.{space_id}")
    delete_rows(ctx, "point_records", couple_space_id=f"eq.{space_id}")
    delete_rows(ctx, "point_items", couple_space_id=f"eq.{space_id}")
    print("已清理旧演示数据")


def create_point_items(ctx: UserCtx, space_id: str) -> dict[str, str]:
    specs = [
        ("关心", "favorite", "care", 0, False),
        ("陪伴", "schedule", "companionship", 1, False),
        ("理解", "spa", "understanding", 2, False),
        ("成长", "fitness_center", "growth", 3, False),
        ("责任", "cleaning_services", "responsibility", 4, False),
        ("仪式感", "card_giftcard", "ritual", 5, False),
        ("激情", "auto_awesome", "passion", 6, False),
        ("日常", "star", None, 7, True),
        ("纪念过去", "bedtime", None, 8, False),
    ]
    result: dict[str, str] = {}
    for name, icon, dimension, sort_order, is_default in specs:
        row = insert_rows(
            ctx,
            "point_items",
            {
                "couple_space_id": space_id,
                "name": name,
                "icon_name": icon,
                "points_per_unit": 10,
                "cycle_type": "month",
                "sort_order": sort_order,
                "is_preset": True,
                "is_enabled": True,
                "is_default": is_default,
                **({"love_dimension": dimension} if dimension else {}),
            },
        )[0]
        result[name] = row["id"]
    print(f"已创建心意项目 {len(result)} 个")
    return result


def insert_record(
    ctx: UserCtx,
    *,
    space_id: str,
    user_id: str,
    point_item_id: str,
    points: int,
    record_at: datetime,
    note: str | None = None,
    love_dimension: str | None = None,
    recipient_comment: str | None = None,
    comment_ctx: UserCtx | None = None,
) -> str:
    row = insert_rows(
        ctx,
        "point_records",
        {
            "couple_space_id": space_id,
            "user_id": user_id,
            "point_item_id": point_item_id,
            "points": points,
            "record_at": iso(record_at),
            "created_at": iso(record_at),
            **({"note": note} if note else {}),
            **({"love_dimension": love_dimension} if love_dimension else {}),
        },
    )[0]
    if recipient_comment:
        rpc(
            comment_ctx or ctx,
            "set_point_record_recipient_comment",
            {"p_record_id": row["id"], "p_comment": recipient_comment},
        )
    return row["id"]


def create_mall_goods(ctx: UserCtx, space_id: str, user_a: str, user_b: str) -> dict[str, str]:
    goods = [
        (user_a, "请你吃一顿想吃的", "工作日辛苦了，周末由我请客安排", 380, 3, "礼物"),
        (user_a, "给你买一本想看的书", "下单前先拉个书单一起挑", 260, 2, "书籍类"),
        (user_a, "周末半日不被打扰", "我来接手杂务，你安心休息", 520, 1, "虚拟类"),
        (user_b, "夜景兜风一次", "路线和歌单都由我准备", 300, None, "礼物"),
        (user_b, "一起去看展/看电影", "挑你最近最想看的那个", 460, 2, "礼物"),
        (user_b, "给你买一个效率工具会员", "选一个你真正在用的工具续费", 680, 1, "科技赋能"),
    ]
    result = {}
    for idx, (owner_id, name, desc, points_required, stock, category) in enumerate(goods):
        row = insert_rows(
            ctx,
            "mall_goods",
            {
                "couple_space_id": space_id,
                "owner_id": owner_id,
                "name": name,
                "description": desc,
                "points_required": points_required,
                "stock": stock,
                "category": category,
                "sort_order": idx,
                "created_at": iso(datetime.now(timezone.utc)),
                "updated_at": iso(datetime.now(timezone.utc)),
            },
        )[0]
        result[name] = row["id"]
    print(f"已创建商城商品 {len(result)} 个")
    return result


def create_exchange_records(ctx: UserCtx, space_id: str, user_a: str, user_b: str, goods: dict[str, str], now: datetime):
    insert_rows(
        ctx,
        "exchange_records",
        [
            {
                "couple_space_id": space_id,
                "user_id": user_a,
                "mall_good_id": goods["夜景兜风一次"],
                "points_spent": 300,
                "created_at": iso(now - timedelta(days=3)),
                "fulfilled_at": iso(now - timedelta(days=2)),
                "fulfilled_by": user_b,
            },
            {
                "couple_space_id": space_id,
                "user_id": user_a,
                "mall_good_id": goods["一起去看展/看电影"],
                "points_spent": 460,
                "created_at": iso(now - timedelta(days=12)),
                "fulfilled_at": None,
                "fulfilled_by": None,
            },
            {
                "couple_space_id": space_id,
                "user_id": user_b,
                "mall_good_id": goods["请你吃一顿想吃的"],
                "points_spent": 380,
                "created_at": iso(now - timedelta(days=7)),
                "fulfilled_at": iso(now - timedelta(days=6)),
                "fulfilled_by": user_a,
            },
            {
                "couple_space_id": space_id,
                "user_id": user_b,
                "mall_good_id": goods["给你买一本想看的书"],
                "points_spent": 260,
                "created_at": iso(now - timedelta(days=20)),
                "fulfilled_at": None,
                "fulfilled_by": None,
            },
        ],
    )
    print("已创建兑换记录 4 条")


def create_deposits(ctx: UserCtx, space_id: str, user_a: str, user_b: str, now: datetime):
    insert_rows(
        ctx,
        "point_deposits",
        [
            {
                "couple_space_id": space_id,
                "user_id": user_a,
                "product_type": "half_year",
                "principal": 300,
                "interest_rate": 0.15,
                "start_at": iso(now - timedelta(days=20)),
                "end_at": iso(now + timedelta(days=160)),
                "status": "active",
                "created_at": iso(now - timedelta(days=20)),
            },
            {
                "couple_space_id": space_id,
                "user_id": user_a,
                "product_type": "quarter",
                "principal": 180,
                "interest_rate": 0.10,
                "start_at": iso(now - timedelta(days=140)),
                "end_at": iso(now - timedelta(days=50)),
                "status": "redeemed",
                "created_at": iso(now - timedelta(days=140)),
            },
            {
                "couple_space_id": space_id,
                "user_id": user_b,
                "product_type": "one_year",
                "principal": 260,
                "interest_rate": 0.20,
                "start_at": iso(now - timedelta(days=35)),
                "end_at": iso(now + timedelta(days=330)),
                "status": "active",
                "created_at": iso(now - timedelta(days=35)),
            },
            {
                "couple_space_id": space_id,
                "user_id": user_b,
                "product_type": "quarter",
                "principal": 120,
                "interest_rate": 0.10,
                "start_at": iso(now - timedelta(days=100)),
                "end_at": iso(now - timedelta(days=10)),
                "status": "redeemed_early",
                "created_at": iso(now - timedelta(days=100)),
            },
        ],
    )
    print("已创建定期存储 4 条")


def seed_demo_data(ctx: UserCtx, ctx_a: UserCtx, ctx_b: UserCtx, space_id: str, user_a: str, user_b: str):
    items = create_point_items(ctx, space_id)
    now = datetime.now(timezone.utc)
    records = [
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_a,
            point_item_id=items["关心"],
            points=180,
            note="加班那周一直接送我，还记得带热饮",
            love_dimension="care",
            record_at=now - timedelta(days=1),
            recipient_comment="那天真的被照顾到了，心里很暖。",
            comment_ctx=ctx_a,
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_a,
            point_item_id=items["陪伴"],
            points=220,
            note="周末陪我跑医院、拿药、排队",
            love_dimension="companionship",
            record_at=now - timedelta(days=4),
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_a,
            point_item_id=items["仪式感"],
            points=260,
            note="悄悄准备了纪念日晚餐和手写卡片",
            love_dimension="ritual",
            record_at=now - timedelta(days=8),
            recipient_comment="这顿饭我会记很久，超有被珍惜的感觉。",
            comment_ctx=ctx_a,
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_a,
            point_item_id=items["成长"],
            points=150,
            note="一起复盘争执，认真聊改进方式",
            love_dimension="growth",
            record_at=now - timedelta(days=13),
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_a,
            point_item_id=items["纪念过去"],
            points=120,
            note="整理了我们从认识到现在的照片合集",
            record_at=now - timedelta(days=25),
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_b,
            point_item_id=items["理解"],
            points=200,
            note="情绪不好时先听我说完，没有急着讲道理",
            love_dimension="understanding",
            record_at=now - timedelta(days=2),
            recipient_comment="以后也想继续这样好好沟通。",
            comment_ctx=ctx_b,
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_b,
            point_item_id=items["责任"],
            points=240,
            note="主动把家里缴费、维修都安排好了",
            love_dimension="responsibility",
            record_at=now - timedelta(days=6),
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_b,
            point_item_id=items["激情"],
            points=180,
            note="约我下班后去看夜景兜风",
            love_dimension="passion",
            record_at=now - timedelta(days=10),
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_b,
            point_item_id=items["日常"],
            points=90,
            note="早起顺手把早餐和咖啡都准备好了",
            record_at=now - timedelta(days=17),
        ),
        insert_record(
            ctx,
            space_id=space_id,
            user_id=user_b,
            point_item_id=items["关心"],
            points=160,
            note="提醒我记得带伞，还把文件复印好",
            love_dimension="care",
            record_at=now - timedelta(days=30),
            recipient_comment="这种细节真的很戳我。",
            comment_ctx=ctx_b,
        ),
    ]

    update_rows(
        ctx,
        "point_records",
        {"edit_used_at": iso(now - timedelta(days=1))},
        id=f"eq.{records[1]}",
    )

    goods = create_mall_goods(ctx, space_id, user_a, user_b)
    create_exchange_records(ctx, space_id, user_a, user_b, goods, now)
    create_deposits(ctx, space_id, user_a, user_b, now)
    request_json(
        "POST",
        rest_url(ctx, "user_deposit_defaults", on_conflict="user_id,couple_space_id"),
        {**ctx.headers, "Prefer": "resolution=merge-duplicates,return=representation"},
        {
            "user_id": user_a,
            "couple_space_id": space_id,
            "product_type": "half_year",
            "updated_at": iso(now),
        },
    )
    request_json(
        "POST",
        rest_url(ctx, "user_deposit_defaults", on_conflict="user_id,couple_space_id"),
        {**ctx.headers, "Prefer": "resolution=merge-duplicates,return=representation"},
        {
            "user_id": user_b,
            "couple_space_id": space_id,
            "product_type": None,
            "updated_at": iso(now),
        },
    )


def main():
    base_url, anon_key = read_env()
    a = sign_in(base_url, anon_key, EMAIL_A, PASSWORD)
    b = sign_in(base_url, anon_key, EMAIL_B, PASSWORD)
    space_id = ensure_couple_space(a, b)
    print(f"已确认情侣空间: {space_id}")
    reset_demo_data(a, space_id)
    seed_demo_data(a, a, b, space_id, a.user_id, b.user_id)
    print(f"演示数据已完成：{EMAIL_A} <-> {EMAIL_B}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
