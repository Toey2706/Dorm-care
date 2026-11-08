// เมนูด้านล่างแชตสองชุด ผู้ที่ยังไม่ผูกห้องเห็นชุด unbound (ค่าเริ่มต้นของบัญชี)
// พอผูกห้องสำเร็จ webhook ผูกชุด bound ให้รายคน ใช้ alias แทนรหัสเมนู
// เพราะรหัสเปลี่ยนทุกครั้งที่สร้างใหม่ แต่ชื่อ alias คงเดิม webhook จึงไม่ต้องเก็บรหัสไว้ที่ไหน

const API = 'https://api.line.me/v2/bot';
const DATA_API = 'https://api-data.line.me/v2/bot';

export const ALIAS = { UNBOUND: 'dorm-unbound', BOUND: 'dorm-bound' };

const W = 2500;
const H = 843;
const areas = (labels) =>
  labels.map((label, i) => {
    const x = Math.round((W / labels.length) * i);
    const width = Math.round((W / labels.length) * (i + 1)) - x;
    return { bounds: { x, y: 0, width, height: H }, action: { type: 'message', label, text: label } };
  });

export const MENUS = {
  [ALIAS.UNBOUND]: {
    image: 'rm-unbound.png',
    body: { size: { width: W, height: H }, selected: true, name: 'ยังไม่ผูกห้อง', chatBarText: 'เมนู', areas: areas(['ผูกเลขห้อง', 'ติดต่อผู้ดูแล']) },
  },
  [ALIAS.BOUND]: {
    image: 'rm-bound.png',
    body: { size: { width: W, height: H }, selected: true, name: 'ผูกห้องแล้ว', chatBarText: 'เมนู', areas: areas(['แจ้งซ่อม', 'ติดตามงาน', 'ติดต่อผู้ดูแล']) },
  },
};

export function richMenuApi(accessToken, fetchImpl = fetch) {
  async function call(method, url, body, contentType = 'application/json') {
    const res = await fetchImpl(url, {
      method,
      headers: { Authorization: `Bearer ${accessToken}`, ...(body !== undefined ? { 'Content-Type': contentType } : {}) },
      body: body === undefined ? undefined : contentType === 'application/json' ? JSON.stringify(body) : body,
    });
    const text = await res.text().catch(() => '');
    if (!res.ok) {
      const err = new Error(`LINE API ${res.status}: ${text}`);
      err.status = res.status;
      throw err;
    }
    return text ? JSON.parse(text) : {};
  }

  return {
    create: (body) => call('POST', `${API}/richmenu`, body).then((r) => r.richMenuId),
    uploadImage: (id, bytes, type) => call('POST', `${DATA_API}/richmenu/${id}/content`, bytes, type),
    remove: (id) => call('DELETE', `${API}/richmenu/${id}`),
    async aliasTarget(aliasId) {
      try {
        return (await call('GET', `${API}/richmenu/alias/${aliasId}`)).richMenuId;
      } catch (err) {
        if (err.status === 404) return null;
        throw err;
      }
    },
    createAlias: (aliasId, richMenuId) => call('POST', `${API}/richmenu/alias`, { richMenuAliasId: aliasId, richMenuId }),
    updateAlias: (aliasId, richMenuId) => call('POST', `${API}/richmenu/alias/${aliasId}`, { richMenuId }),
    setDefault: (id) => call('POST', `${API}/user/all/richmenu/${id}`),
    bulkLink: (id, userIds) => call('POST', `${API}/richmenu/bulk/link`, { richMenuId: id, userIds }),
    bulkUnlink: (userIds) => call('POST', `${API}/richmenu/bulk/unlink`, { userIds }),
    link: (userId, id) => call('POST', `${API}/user/${encodeURIComponent(userId)}/richmenu/${id}`),
    unlink: (userId) => call('DELETE', `${API}/user/${encodeURIComponent(userId)}/richmenu`),
  };
}

const chunks = (list, size) => Array.from({ length: Math.ceil(list.length / size) }, (_, i) => list.slice(i * size, i * size + size));

/**
 * สร้างเมนูทั้งสองชุดใหม่ ชี้ alias มาที่ชุดใหม่ แล้วลบชุดเก่า รันซ้ำได้
 * activeUserIds = ผู้ที่ผูกห้องอยู่ ได้ชุด bound ส่วน revokedUserIds กลับไปใช้ค่าเริ่มต้น
 */
export async function setupRichMenus({ api, loadImage, activeUserIds, revokedUserIds }) {
  const ids = {};
  for (const [alias, menu] of Object.entries(MENUS)) {
    const id = await api.create(menu.body);
    const { bytes, type } = await loadImage(menu.image);
    await api.uploadImage(id, bytes, type);
    const old = await api.aliasTarget(alias);
    if (old) await api.updateAlias(alias, id);
    else await api.createAlias(alias, id);
    if (old && old !== id) await api.remove(old).catch(() => {});
    ids[alias] = id;
  }
  await api.setDefault(ids[ALIAS.UNBOUND]);
  // LINE รับครั้งละไม่เกิน 500 คน
  for (const group of chunks(activeUserIds, 500)) await api.bulkLink(ids[ALIAS.BOUND], group);
  const revoked = revokedUserIds.filter((u) => !activeUserIds.includes(u));
  for (const group of chunks(revoked, 500)) await api.bulkUnlink(group);
  return { menus: ids, linked: activeUserIds.length, unlinked: revoked.length };
}
