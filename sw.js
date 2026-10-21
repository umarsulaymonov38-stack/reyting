// Yuksalish veb-ilovasi: har doim avval internetdan ENG YANGI versiya olinadi,
// internet bo'lmasa — oxirgi saqlangan nusxa ochiladi. Ma'lumotlar (Supabase) keshlanmaydi.
const CACHE = 'yuksalish-v2';
const CORE = ['./', 'index.html', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'img/oquvchi.jpg'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET') return;
  // Supabase kutubxonasi (versiyasi qat'iy, o'zgarmaydi): bir marta yuklab, keshdan beriladi — tezroq ochiladi
  if (url.hostname === 'cdn.jsdelivr.net' || url.hostname === 'unpkg.com') {
    e.respondWith(caches.match(req).then(r => r || fetch(req).then(res => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
      return res;
    })));
    return;
  }
  if (url.origin !== location.origin) return; // API (Supabase) va boshqa saytlar — keshlanmaydi
  e.respondWith(
    fetch(req, { cache: 'no-cache' })
      .then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
        return res;
      })
      .catch(() => caches.match(req).then(r => r || (req.mode === 'navigate' ? caches.match('index.html') : undefined)))
  );
});
