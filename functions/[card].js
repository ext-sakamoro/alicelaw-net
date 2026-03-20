// ALICE Metal Card — 動的QRリダイレクトルーター
// Pages Function: /0x01, /0x02, ... のパスをインターセプトしてリダイレクト
//
// ルーティング優先順位:
//   1. campaigns (期間限定) — 最優先
//   2. schedules (時間帯)   — 中優先
//   3. defaults              — フォールバック
//
// KV移行後: env.ALICE_ROUTES から読み込み
// 現在: コード内ROUTES定数で管理

const ROUTES = {
  "0x01": {
    default: {
      url: "https://github.com/ext-sakamoro/ALICE-SDF",
      status: 302
    },
    schedule: {
      timezone: "Asia/Tokyo",
      rules: [
        { name: "daytime",  hours: [9, 18],  url: "https://github.com/ext-sakamoro/ALICE-SDF" },
        { name: "evening",  hours: [18, 24], url: "https://alicelaw.net/sdf-metaverse.html" },
        { name: "night",    hours: [0, 9],   url: "https://alicelaw.net/" }
      ]
    },
    campaigns: []
  }
};

function getJSTHour() {
  const now = new Date();
  // UTC+9
  const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  return jst.getUTCHours();
}

function findActiveCampaign(campaigns) {
  if (!campaigns || campaigns.length === 0) return null;
  const now = new Date();
  for (const c of campaigns) {
    if (!c.active) continue;
    const start = new Date(c.start);
    const end = new Date(c.end);
    if (now >= start && now <= end) return c;
  }
  return null;
}

function findScheduleUrl(schedule) {
  if (!schedule || !schedule.rules) return null;
  const hour = getJSTHour();
  for (const rule of schedule.rules) {
    const [from, to] = rule.hours;
    if (from <= to) {
      if (hour >= from && hour < to) return rule.url;
    } else {
      // 跨ぎ (例: 22-6)
      if (hour >= from || hour < to) return rule.url;
    }
  }
  return null;
}

export async function onRequest(context) {
  const { params } = context;
  const cardId = params.card;

  // /0x01 ~ /0xFF 以外は静的ファイルへフォールバック
  if (!/^0x[0-9a-fA-F]{1,2}$/.test(cardId)) {
    return context.next();
  }

  const route = ROUTES[cardId.toLowerCase()];
  if (!route) {
    // 未登録カード → トップページ
    return Response.redirect("https://alicelaw.net/", 302);
  }

  // 1. キャンペーンチェック
  const campaign = findActiveCampaign(route.campaigns);
  if (campaign) {
    return Response.redirect(campaign.url, campaign.status || 302);
  }

  // 2. 時間帯チェック
  const scheduleUrl = findScheduleUrl(route.schedule);
  if (scheduleUrl) {
    return Response.redirect(scheduleUrl, 302);
  }

  // 3. デフォルト
  if (route.default) {
    return Response.redirect(route.default.url, route.default.status || 302);
  }

  return Response.redirect("https://alicelaw.net/", 302);
}
