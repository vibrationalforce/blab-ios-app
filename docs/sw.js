/**
 * Echoelmusic Service Worker
 * Enables offline functionality and caching for PWA
 *
 * Future-proof for: WebXR (glasses), Web Bluetooth (wearables),
 * Background Sync, Push Notifications
 */

const CACHE_NAME = 'echoelmusic-v10.22.0';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/404.html',
  '/shared.css',
  '/shared.js',
  '/favicon.svg',
  '/app-icon.svg',
  '/manifest.json',
  '/version.json',
  '/fonts/atkinson-regular.woff2',
  '/fonts/atkinson-bold.woff2',
  '/fonts/atkinson-italic.woff2',
  '/privacy.html',
  '/terms.html',
  '/impressum.html',
  '/tools.html',
  '/faq.html',
  '/support.html',
  '/health.html',
  '/security.html',
  '/accessibility.html'
];

const MAX_CACHE_ITEMS = 50;
async function trimCache(cacheName, maxItems) {
  const cache = await caches.open(cacheName);
  const keys = await cache.keys();
  if (keys.length > maxItems) {
    await Promise.all(keys.slice(0, keys.length - maxItems).map(k => cache.delete(k)));
  }
}

// Install: Cache static assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[SW] Caching static assets');
      return cache.addAll(STATIC_ASSETS);
    })
  );
  self.skipWaiting();
});

// Activate: Nuke ALL old caches, re-cache fresh assets, notify clients
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => {
            console.log('[SW] Removing old cache:', key);
            return caches.delete(key);
          })
      );
    }).then(() => {
      // Re-cache fresh copies of all static assets (network fetch, bypass old cache)
      return caches.open(CACHE_NAME).then((cache) => {
        return Promise.all(
          STATIC_ASSETS.map((url) =>
            fetch(url, { cache: 'no-store' })
              .then((response) => {
                if (response.ok) return cache.put(url, response);
              })
              .catch(() => {}) // Offline: skip, install already cached these
          )
        );
      });
    }).then(() => {
      return trimCache(CACHE_NAME, MAX_CACHE_ITEMS);
    }).then(() => {
      return self.clients.matchAll().then(clients => {
        clients.forEach(client => client.postMessage({ type: 'SW_UPDATED', version: CACHE_NAME }));
      });
    })
  );
  self.clients.claim();
});

function fetchBypassCache(request, timeout = 5000) {
  // Create a no-cache request to bypass browser HTTP cache AND CDN edge cache
  const noCacheRequest = new Request(request.url, {
    method: request.method,
    headers: request.headers,
    mode: request.mode,
    credentials: request.credentials,
    redirect: request.redirect,
    cache: 'no-store'
  });
  return Promise.race([
    fetch(noCacheRequest),
    new Promise((_, reject) => setTimeout(() => reject(new Error('Network timeout')), timeout))
  ]);
}

function fetchWithTimeout(request, timeout = 5000) {
  return Promise.race([
    fetch(request),
    new Promise((_, reject) => setTimeout(() => reject(new Error('Network timeout')), timeout))
  ]);
}

// Fetch: Network-first with cache fallback
self.addEventListener('fetch', (event) => {
  // Skip non-GET requests
  if (event.request.method !== 'GET') return;

  // Skip cross-origin requests
  if (!event.request.url.startsWith(self.location.origin)) return;

  const url = new URL(event.request.url);

  // Cache-first for immutable assets (fonts, images)
  if (url.pathname.startsWith('/fonts/') || url.pathname.endsWith('.svg') || url.pathname.endsWith('.png')) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request).then((response) => {
          if (response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        });
      })
    );
    return;
  }

  // HTML + version.json: Network-first with cache:no-store (bypasses CDN)
  const isHTML = event.request.mode === 'navigate' || url.pathname.endsWith('.html') || url.pathname === '/';
  const isVersionCheck = url.pathname === '/version.json';

  if (isHTML || isVersionCheck) {
    event.respondWith(
      fetchBypassCache(event.request)
        .then((response) => {
          if (response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        })
        .catch(() => {
          return caches.match(event.request).then((cached) => {
            if (cached) return cached;
            if (isHTML) return caches.match('/404.html');
          });
        })
    );
    return;
  }

  // CSS/JS: Stale-while-revalidate (serve cached, fetch fresh in background)
  if (url.pathname.endsWith('.css') || url.pathname.endsWith('.js')) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        const networkFetch = fetchWithTimeout(event.request).then((response) => {
          if (response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        });
        return cached || networkFetch;
      })
    );
    return;
  }

  // Everything else: Network-first with cache fallback
  event.respondWith(
    fetchWithTimeout(event.request)
      .then((response) => {
        if (response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => {
        return caches.match(event.request).then((cached) => {
          if (cached) return cached;
          if (event.request.mode === 'navigate') return caches.match('/404.html');
        });
      })
  );
});

// Background Sync (future: sync bio data when back online)
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-biodata') {
    console.log('[SW] Background sync: biodata');
    // Future: Sync accumulated biometric data
  }
});

// Push Notifications (future: coherence reminders)
self.addEventListener('push', (event) => {
  if (event.data) {
    const data = event.data.json();
    event.waitUntil(
      self.registration.showNotification(data.title || 'Echoelmusic', {
        body: data.body || 'Time for your coherence session',
        icon: '/favicon.svg',
        badge: '/favicon.svg',
        vibrate: [100, 50, 100],
        tag: 'echoelmusic-notification',
        data: data
      })
    );
  }
});

// Notification click handler
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then((clientList) => {
      // Focus existing window or open new
      for (const client of clientList) {
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});

// Message handler for future WebXR/Bluetooth coordination
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  // Future: Handle WebXR session state
  if (event.data && event.data.type === 'XR_SESSION_START') {
    console.log('[SW] WebXR session started');
  }

  // Future: Handle Web Bluetooth device connection
  if (event.data && event.data.type === 'BLUETOOTH_CONNECTED') {
    console.log('[SW] Bluetooth device connected:', event.data.device);
  }
});

console.log('[SW] Echoelmusic Service Worker loaded');
