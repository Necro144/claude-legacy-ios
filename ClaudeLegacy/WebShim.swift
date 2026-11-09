import Foundation

enum WebShim {
    /// Presents the web view as a recent Safari so the site's "out of date" check passes.
    static let newerUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    static let honestUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4.1 Mobile/15E148 Safari/604.1"

    static var userAgent: String {
        let spoof = UserDefaults.standard.object(forKey: "spoofUA") as? Bool ?? true
        return spoof ? newerUserAgent : honestUserAgent
    }

    /// Runs on every page before the site's own code: fills in newer JavaScript features,
    /// paints the page black, hides "out of date" notices, and reports errors to the app.
    static var script: String {
        let css = Provider.darkCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: " ")
        // TEST_NOHIDE is only used by the automated simulator test.
        let noHide = ProcessInfo.processInfo.environment["TEST_NOHIDE"] != nil ? "window.__noHide = true;" : ""
        return noHide + #"""
        (function () {
          function post(msg) {
            try { window.webkit.messageHandlers.jsError.postMessage(String(msg)); } catch (e) {}
          }
          try {
            if (!Promise.withResolvers) {
              Promise.withResolvers = function () {
                var resolve, reject;
                var promise = new Promise(function (a, b) { resolve = a; reject = b; });
                return { promise: promise, resolve: resolve, reject: reject };
              };
            }
            if (!Object.groupBy) {
              Object.groupBy = function (items, fn) {
                var out = Object.create(null), i = 0;
                for (var x of items) { var k = fn(x, i++); (out[k] || (out[k] = [])).push(x); }
                return out;
              };
            }
            if (!Map.groupBy) {
              Map.groupBy = function (items, fn) {
                var out = new Map(), i = 0;
                for (var x of items) { var k = fn(x, i++); if (!out.has(k)) out.set(k, []); out.get(k).push(x); }
                return out;
              };
            }
            if (!Array.fromAsync) {
              Array.fromAsync = async function (items, fn) {
                var out = [], i = 0;
                for await (var x of items) { out.push(fn ? await fn(x, i) : x); i++; }
                return out;
              };
            }
            if (!URL.canParse) {
              URL.canParse = function (u, b) { try { new URL(u, b); return true; } catch (e) { return false; } };
            }
            if (typeof AbortSignal !== 'undefined' && !AbortSignal.any) {
              AbortSignal.any = function (signals) {
                var c = new AbortController();
                signals.forEach(function (s) {
                  if (s.aborted) c.abort(s.reason);
                  else s.addEventListener('abort', function () { c.abort(s.reason); });
                });
                return c.signal;
              };
            }
            var sp = Set.prototype;
            function keys(o) { return Array.from(o.keys ? o.keys() : o); }
            if (!sp.union) sp.union = function (o) { var r = new Set(this); keys(o).forEach(function (v) { r.add(v); }); return r; };
            if (!sp.intersection) sp.intersection = function (o) { var r = new Set(); Array.from(this).forEach(function (v) { if (o.has(v)) r.add(v); }); return r; };
            if (!sp.difference) sp.difference = function (o) { var r = new Set(); Array.from(this).forEach(function (v) { if (!o.has(v)) r.add(v); }); return r; };
            if (!sp.symmetricDifference) sp.symmetricDifference = function (o) { var r = new Set(this); keys(o).forEach(function (v) { if (r.has(v)) r.delete(v); else r.add(v); }); return r; };
            if (!sp.isSubsetOf) sp.isSubsetOf = function (o) { return Array.from(this).every(function (v) { return o.has(v); }); };
            if (!sp.isSupersetOf) sp.isSupersetOf = function (o) { var s = this; return keys(o).every(function (v) { return s.has(v); }); };
            if (!sp.isDisjointFrom) sp.isDisjointFrom = function (o) { return !Array.from(this).some(function (v) { return o.has(v); }); };

            if (!Promise.try) {
              Promise.try = function (fn) {
                var args = Array.prototype.slice.call(arguments, 1);
                return new Promise(function (resolve) { resolve(fn.apply(null, args)); });
              };
            }
            if (window.ReadableStream && !ReadableStream.prototype[Symbol.asyncIterator]) {
              ReadableStream.prototype[Symbol.asyncIterator] = function () {
                var reader = this.getReader();
                return {
                  next: function () { return reader.read(); },
                  return: function () { reader.releaseLock(); return Promise.resolve({ done: true, value: undefined }); },
                  [Symbol.asyncIterator]: function () { return this; }
                };
              };
              ReadableStream.prototype.values = ReadableStream.prototype[Symbol.asyncIterator];
            }
            if (window.Element && !Element.prototype.checkVisibility) {
              Element.prototype.checkVisibility = function () { return !!(this.offsetWidth || this.offsetHeight || this.getClientRects().length); };
            }
            if (typeof Iterator === 'undefined') {
              var IterProto = Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));
              var IteratorShim = function Iterator() {};
              IteratorShim.prototype = IterProto;
              IteratorShim.from = function (o) { return o[Symbol.iterator] ? o[Symbol.iterator]() : o; };
              window.Iterator = IteratorShim;
              var wrap = function (it) { return { [Symbol.iterator]: function () { return it; } }; };
              IterProto.map = function (fn) { var s = this; return (function* () { var i = 0; for (var x of wrap(s)) yield fn(x, i++); })(); };
              IterProto.filter = function (fn) { var s = this; return (function* () { var i = 0; for (var x of wrap(s)) if (fn(x, i++)) yield x; })(); };
              IterProto.take = function (n) { var s = this; return (function* () { var i = 0; if (n <= 0) return; for (var x of wrap(s)) { yield x; if (++i >= n) return; } })(); };
              IterProto.drop = function (n) { var s = this; return (function* () { var i = 0; for (var x of wrap(s)) if (i++ >= n) yield x; })(); };
              IterProto.flatMap = function (fn) { var s = this; return (function* () { var i = 0; for (var x of wrap(s)) yield* wrap(fn(x, i++)[Symbol.iterator]()); })(); };
              IterProto.toArray = function () { return Array.from(wrap(this)); };
              IterProto.forEach = function (fn) { var i = 0; for (var x of wrap(this)) fn(x, i++); };
              IterProto.some = function (fn) { var i = 0; for (var x of wrap(this)) if (fn(x, i++)) return true; return false; };
              IterProto.every = function (fn) { var i = 0; for (var x of wrap(this)) if (!fn(x, i++)) return false; return true; };
              IterProto.find = function (fn) { var i = 0; for (var x of wrap(this)) if (fn(x, i++)) return x; return undefined; };
              IterProto.reduce = function (fn, init) { var acc = init, first = arguments.length < 2, i = 0; for (var x of wrap(this)) { if (first) { acc = x; first = false; } else acc = fn(acc, x, i); i++; } return acc; };
            }
            if (!window.requestIdleCallback) {
              window.requestIdleCallback = function (cb) { return setTimeout(function () { cb({ didTimeout: false, timeRemaining: function () { return 10; } }); }, 1); };
              window.cancelIdleCallback = function (id) { clearTimeout(id); };
            }
          } catch (e) { post('shim: ' + e); }



          // Downloads of files the page builds in memory (blob: links). The page clicks a hidden download link and then
          // immediately discards the file, which the iPhone's own download system is too slow to catch. So take the file
          // right away, send it to the app in pieces, and let the app save it and open the share sheet.
          try {
            var realAnchorClick = HTMLAnchorElement.prototype.click;
            var sendCount = 0;
            var sendBlob = function (blob, name) {
              var id = String(Date.now()) + '-' + (sendCount++);
              var reader = new FileReader();
              reader.onload = function () {
                var text = String(reader.result), base64 = text.slice(text.indexOf(',') + 1);
                var piece = 1000000 - (1000000 % 4), total = Math.max(1, Math.ceil(base64.length / piece));
                for (var i = 0; i < total; i++) {
                  window.webkit.messageHandlers.saveFile.postMessage({ id: id, name: name, index: i, total: total, data: base64.slice(i * piece, (i + 1) * piece) });
                }
              };
              reader.onerror = function () { post('download read failed'); };
              reader.readAsDataURL(blob);
            };
            var takeBlobLink = function (a) {
              if (!a || !a.href || !/^blob:/.test(a.href) || !a.hasAttribute('download')) return false;
              var name = a.getAttribute('download') || 'download';
              post('download from blob: ' + name);
              fetch(a.href).then(function (r) { return r.blob(); }).then(function (b) { sendBlob(b, name); })
                .catch(function (e) { post('download failed: ' + e); });
              return true;
            };
            HTMLAnchorElement.prototype.click = function () {
              if (takeBlobLink(this)) return;
              return realAnchorClick.apply(this, arguments);
            };
            document.addEventListener('click', function (e) {
              var a = e.target && e.target.closest ? e.target.closest('a') : null;
              if (a && takeBlobLink(a)) { e.preventDefault(); e.stopImmediatePropagation(); }
            }, true);
          } catch (e) { post('download hook: ' + e); }

          // Tell the page it is running as an installed app, so it skips "open the app" and "add to home screen" prompts.
          try {
            Object.defineProperty(navigator, 'standalone', { get: function () { return true; }, configurable: true });
            var realMatchMedia = window.matchMedia.bind(window);
            window.matchMedia = function (q) {
              var text = String(q);
              var standalone = /display-mode:\s*(standalone|minimal-ui)/i.test(text);
              var browser = /display-mode:\s*browser/i.test(text);
              if (!standalone && !browser) return realMatchMedia(q);
              return {
                matches: standalone, media: text, onchange: null,
                addListener: function () {}, removeListener: function () {},
                addEventListener: function () {}, removeEventListener: function () {},
                dispatchEvent: function () { return false; }
              };
            };
          } catch (e) { post('standalone: ' + e); }

          try {
            var style = document.createElement('style');
            style.textContent = `__CSS__`;
            (document.head || document.documentElement).appendChild(style);
          } catch (e) { post('css: ' + e); }

          // Removes "out of date" notices and "get the app" prompts, so the page behaves like it is already inside the app.
          var outdated = /software is out of date|browser is out of date|update your browser|unsupported browser/i;
          var appPrompt = /$^/;
          var appButton = /$^/;
          function unlock() {
            [document.body, document.documentElement].forEach(function (el) {
              if (!el) return;
              el.style.removeProperty('pointer-events');
              el.style.removeProperty('overflow');
              el.removeAttribute('data-scroll-locked');
            });
          }
          function hideOverlays() {
            try {
              if (window.__noHide || !document.body) return;
              var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
              var n, hidAny = false;
              while ((n = w.nextNode())) {
                var t = n.nodeValue || '';
                if (!t || t.length > 400) continue;
                var el = n.parentElement;
                if (!el) continue;
                if (outdated.test(t)) {
                  var hops = 0;
                  while (el.parentElement && hops < 4 && el.parentElement !== document.body &&
                         (el.parentElement.textContent || '').length < 500) { el = el.parentElement; hops++; }
                  el.style.display = 'none';
                } else if (appPrompt.test(t)) {
                  // climb to the pop-up's outermost wrapper (a direct child of <body>) and remove it with its backdrop
                  var start = el;
                  while (el.parentElement && el.parentElement !== document.body) el = el.parentElement;
                  if (el && el !== document.body && (el.textContent || '').length < 800) { el.style.display = 'none'; hidAny = true; }
                  else {
                    // a banner inside the page: hide the nearest fixed or sticky box around the text
                    var box = start, climbed = 0;
                    while (box && box !== document.body && climbed < 8) {
                      var pos = getComputedStyle(box).position;
                      if (pos === 'fixed' || pos === 'sticky') { box.style.display = 'none'; hidAny = true; break; }
                      box = box.parentElement; climbed++;
                    }
                  }
                } else if (appButton.test(t)) {
                  var b = el.closest('button, a, [role="button"]') || el;
                  b.style.display = 'none';
                }
              }
              if (hidAny) unlock();
            } catch (e) {}
          }
          var hideTimer = null;
          function scheduleHide() { if (hideTimer) return; hideTimer = setTimeout(function () { hideTimer = null; hideOverlays(); }, 250); }
          try { new MutationObserver(scheduleHide).observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
          setInterval(hideOverlays, 1500);

          var oldError = console.error;
          console.error = function () {
            post('console: ' + Array.prototype.slice.call(arguments).join(' ').slice(0, 300));
            return oldError.apply(console, arguments);
          };
          window.addEventListener('error', function (e) {
            post((e.message || 'error') + ' @ ' + (e.filename || '') + ':' + (e.lineno || 0) + ' [' + location.href + ']');
          });
          window.addEventListener('unhandledrejection', function (e) {
            var r = e.reason;
            post('promise: ' + (r && (r.stack || r.message) || r) + ' [' + location.href + ']');
          });
        })();
        """#.replacingOccurrences(of: "__CSS__", with: css)
    }
}
