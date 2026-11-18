/*
 * 3wordPasGen のオフライン用 Service Worker
 *
 * - 初回に下のファイルを端末（ブラウザ）の中に保存し、以後は保存した物だけを使う。
 * - ネットからの再読み込みはしないので、機内モードでも動く。
 *   また、公開中のページが後から書き換えられても、保存済みの物は変わらない。
 * - アプリを更新したときは CACHE_VERSION の数字を上げる。
 *   ブラウザは sw.js の変更を検知したときだけ、新しいファイルを保存し直す。
 */
const CACHE_VERSION = "3wordpasgen-v2";

const FILES = [
  "./3wordPasGen.html",
  "./manifest.webmanifest",
  "./icons/apple-touch-icon.png",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then((cache) => cache.addAll(FILES.map((f) => new Request(f, { cache: "reload" }))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(
    caches.match(request, { ignoreSearch: true }).then((cached) => cached || fetch(request))
  );
});
