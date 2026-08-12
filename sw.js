/* 돌봄(dolbom) Service Worker — 현장(요양시설·지하주차장 등) 통신 불안정 대비
   · 앱 화면은 캐시 우선으로 즉시 실행
   · Supabase API는 네트워크 우선, 실패 시 마지막 응답 사용
   버전을 올리면 사용자 기기에서 자동 갱신됩니다. */
const V = 'dolbom-v2';
const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(V).then(c => c.addAll(SHELL).catch(() => {})));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Supabase / 외부 API — 네트워크 우선, 실패하면 캐시
  if (url.origin !== location.origin) {
    e.respondWith(
      fetch(req).then(res => {
        if (res.ok && url.pathname.includes('/rest/v1/')) {
          const copy = res.clone();
          caches.open(V).then(c => c.put(req, copy));
        }
        return res;
      }).catch(() => caches.match(req))
    );
    return;
  }

  // 앱 파일 — 캐시 우선, 백그라운드 갱신
  e.respondWith(
    caches.match(req).then(hit => {
      const net = fetch(req).then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(V).then(c => c.put(req, copy)); }
        return res;
      }).catch(() => hit);
      return hit || net;
    })
  );
});

self.addEventListener('message', e => { if (e.data === 'skipWaiting') self.skipWaiting(); });
