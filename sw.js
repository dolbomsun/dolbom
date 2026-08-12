/* 돌봄(dolbom) Service Worker — 현장(요양시설·지하주차장 등) 통신 불안정 대비
   · 앱 코드(index.html)는 "네트워크 우선" — 항상 최신 버전을 먼저 확인하고,
     인터넷이 끊겼을 때만 캐시본으로 실행합니다. (기기마다 옛 버전이 남는 문제 방지)
   · 아이콘·매니페스트 같은 정적 자원은 캐시 우선
   · Supabase API는 네트워크 우선, 실패 시 마지막 응답 사용 */
const V = 'dolbom-v6';
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

// 앱 코드인지(=항상 최신이어야 하는지) 판단
function isAppShell(url) {
  return url.origin === location.origin &&
         (url.pathname.endsWith('/') ||
          url.pathname.endsWith('/index.html') ||
          url.pathname.endsWith('/sw.js'));
}

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

  // 앱 코드 — 네트워크 우선(최신 보장), 오프라인일 때만 캐시본
  if (isAppShell(url) || req.mode === 'navigate') {
    e.respondWith(
      fetch(req).then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(V).then(c => c.put(req, copy)); }
        return res;
      }).catch(() => caches.match(req).then(hit => hit || caches.match('./index.html')))
    );
    return;
  }

  // 아이콘 등 정적 자원 — 캐시 우선, 백그라운드 갱신
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
