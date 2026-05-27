/* Echoelmusic Shared JS — v10.2.0 */
(function(){
var V='10.9.1';

/* === Burger Menu === */
var burger=document.getElementById('burger');
var overlay=document.getElementById('menuOverlay');
if(burger&&overlay){
function toggleMenu(){
var open=burger.classList.toggle('active');
overlay.classList.toggle('open');
burger.setAttribute('aria-expanded',open);
burger.setAttribute('aria-label',open?'Close menu':'Open menu');
document.body.style.overflow=open?'hidden':'';
}
burger.addEventListener('click',toggleMenu);
overlay.querySelectorAll('a').forEach(function(a){
a.addEventListener('click',function(){if(burger.classList.contains('active'))toggleMenu();});
});
document.addEventListener('keydown',function(e){
if(e.key==='Escape'&&burger.classList.contains('active'))toggleMenu();
if(e.key==='Tab'&&burger.classList.contains('active')){
var focusable=overlay.querySelectorAll('a[href],button,[tabindex]:not([tabindex="-1"])');
var first=focusable[0];var last=focusable[focusable.length-1];
if(e.shiftKey){if(document.activeElement===first||!overlay.contains(document.activeElement)){e.preventDefault();last.focus();}}
else{if(document.activeElement===last||!overlay.contains(document.activeElement)){e.preventDefault();first.focus();}}
}
});
}

/* === Service Worker: register with updateViaCache:none === */
if('serviceWorker' in navigator){
navigator.serviceWorker.register('/sw.js',{updateViaCache:'none'}).then(function(reg){
reg.addEventListener('updatefound',function(){
var nw=reg.installing;
if(nw){nw.addEventListener('statechange',function(){
if(nw.state==='activated'){window.location.reload();}
});}
});
setInterval(function(){reg.update();},30000);
}).catch(function(e){console.warn('[SW]',e);});
navigator.serviceWorker.addEventListener('message',function(e){
if(e.data&&e.data.type==='SW_UPDATED'){window.location.reload();}
});
}

/* === Periodic Version Poll: detect deploy while page is open === */
function checkVersion(){
fetch('/version.json?_='+Date.now(),{cache:'no-store'}).then(function(r){return r.json();}).then(function(d){
if(d.version&&d.version!==V){
var K='echoel-nuke',t=sessionStorage.getItem(K);
if(t&&Date.now()-parseInt(t)<60000)return;
sessionStorage.setItem(K,''+Date.now());
var p=[];
if('caches' in window)p.push(caches.keys().then(function(ks){return Promise.all(ks.map(function(k){return caches.delete(k)}))}));
if(navigator.serviceWorker)p.push(navigator.serviceWorker.getRegistrations().then(function(rs){return Promise.all(rs.map(function(r){return r.unregister()}))}));
Promise.all(p).then(function(){window.location.reload()});
}
}).catch(function(){});
}
setInterval(checkVersion,60000);
})();
