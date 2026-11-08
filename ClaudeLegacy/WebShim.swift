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
        return #"""
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
            if (!window.requestIdleCallback) {
              window.requestIdleCallback = function (cb) { return setTimeout(function () { cb({ didTimeout: false, timeRemaining: function () { return 10; } }); }, 1); };
              window.cancelIdleCallback = function (id) { clearTimeout(id); };
            }
          } catch (e) { post('shim: ' + e); }

          try {
            var style = document.createElement('style');
            style.textContent = `__CSS__`;
            (document.head || document.documentElement).appendChild(style);
          } catch (e) { post('css: ' + e); }

          function hideOutdated() {
            try {
              if (!document.body) return;
              var re = /software is out of date|browser is out of date|update your browser|unsupported browser/i;
              var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
              var n;
              while ((n = w.nextNode())) {
                if (re.test(n.nodeValue || '')) {
                  var el = n.parentElement, hops = 0;
                  while (el && el.parentElement && hops < 4 && el.parentElement !== document.body &&
                         (el.parentElement.textContent || '').length < 500) { el = el.parentElement; hops++; }
                  if (el) el.style.display = 'none';
                }
              }
            } catch (e) {}
          }
          setInterval(hideOutdated, 1500);

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
