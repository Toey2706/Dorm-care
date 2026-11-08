import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ALIAS, MENUS, setupRichMenus } from '../_shared/richmenu.js';

function fakeApi(existing = {}) {
  const calls = [];
  const aliases = { ...existing };
  let n = 0;
  return {
    calls,
    aliases,
    api: {
      create: async (body) => { calls.push(['create', body.name]); return `rm${++n}`; },
      uploadImage: async (id) => calls.push(['image', id]),
      aliasTarget: async (a) => aliases[a] || null,
      createAlias: async (a, id) => { aliases[a] = id; calls.push(['createAlias', a]); },
      updateAlias: async (a, id) => { aliases[a] = id; calls.push(['updateAlias', a]); },
      remove: async (id) => calls.push(['remove', id]),
      setDefault: async (id) => calls.push(['default', id]),
      bulkLink: async (id, users) => calls.push(['link', id, users.length]),
      bulkUnlink: async (users) => calls.push(['unlink', users]),
    },
  };
}
const loadImage = async () => ({ bytes: new Uint8Array([1]), type: 'image/png' });

test('พื้นที่กดของเมนูต่อกันพอดีเต็มความกว้าง 2500', () => {
  for (const m of Object.values(MENUS)) {
    const a = m.body.areas;
    assert.equal(a[0].bounds.x, 0);
    assert.equal(a.at(-1).bounds.x + a.at(-1).bounds.width, 2500);
    for (let i = 1; i < a.length; i += 1) assert.equal(a[i].bounds.x, a[i - 1].bounds.x + a[i - 1].bounds.width);
  }
  assert.deepEqual(MENUS[ALIAS.UNBOUND].body.areas.map((x) => x.action.text), ['ผูกเลขห้อง', 'ติดต่อผู้ดูแล']);
});

test('รันครั้งแรก สร้าง alias ตั้งเมนูเริ่มต้น และผูกเมนูให้คนที่ผูกห้องอยู่', async () => {
  const f = fakeApi();
  const users = Array.from({ length: 501 }, (_, i) => `U${i}`);
  const r = await setupRichMenus({ api: f.api, loadImage, activeUserIds: users, revokedUserIds: ['U0', 'X'] });
  assert.equal(f.aliases[ALIAS.UNBOUND], r.menus[ALIAS.UNBOUND]);
  assert.ok(f.calls.some((c) => c[0] === 'default' && c[1] === r.menus[ALIAS.UNBOUND]));
  assert.deepEqual(f.calls.filter((c) => c[0] === 'link').map((c) => c[2]), [500, 1]);
  // U0 กลับมาผูกห้องใหม่แล้ว ไม่ต้องถอดเมนู
  assert.deepEqual(f.calls.find((c) => c[0] === 'unlink'), ['unlink', ['X']]);
});

test('รันซ้ำ ย้าย alias ไปชุดใหม่และลบชุดเก่า', async () => {
  const f = fakeApi({ [ALIAS.UNBOUND]: 'old1', [ALIAS.BOUND]: 'old2' });
  await setupRichMenus({ api: f.api, loadImage, activeUserIds: [], revokedUserIds: [] });
  assert.ok(f.calls.some((c) => c[0] === 'remove' && c[1] === 'old1'));
  assert.ok(f.calls.some((c) => c[0] === 'remove' && c[1] === 'old2'));
  assert.equal(f.calls.filter((c) => c[0] === 'createAlias').length, 0);
});
