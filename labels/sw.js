// Inkline Labels offline copy: the page always loads fresh when there's a connection, and from the last copy
// saved here when there isn't (a warehouse corner with no Wi-Fi). The printer itself is Bluetooth, so printing
// works offline once the page is open.
const CACHE = 'inkline-labels-1';
const FILES = ['./', './manifest.webmanifest', '../Inkline-256.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  const isPage = req.mode === 'navigate';
  e.respondWith(
    fetch(req).then(res => {
      if (res.ok) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(isPage ? './' : req, copy));   // any ?items=... link saves as the one page
      }
      return res;
    }).catch(() => caches.match(isPage ? './' : req, { ignoreSearch: isPage }))
  );
});
