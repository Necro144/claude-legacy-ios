import Foundation

/// Collects JavaScript errors from the Claude page so they can be read in Settings > Diagnostics.
final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()
    @Published var items: [String] = []

    func add(_ text: String) {
        DispatchQueue.main.async {
            self.items.append(text)
            if self.items.count > 60 { self.items.removeFirst() }
        }
    }

    func clear() { items.removeAll() }
}

enum WebShim {
    /// Safari's own user agent, so the site treats this like Safari on iOS 16.4.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4.1 Mobile/15E148 Safari/604.1"

    /// Fills in newer JavaScript features that the iOS 16 web engine lacks, and reports page errors.
    static let script = #"""
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
        if (!sp.union) sp.union = function (o) { var r = new Set(this); o.keys ? Array.from(o.keys()).forEach(function (v) { r.add(v); }) : Array.from(o).forEach(function (v) { r.add(v); }); return r; };
        if (!sp.intersection) sp.intersection = function (o) { var self = this, r = new Set(); Array.from(self).forEach(function (v) { if (o.has(v)) r.add(v); }); return r; };
        if (!sp.difference) sp.difference = function (o) { var r = new Set(); Array.from(this).forEach(function (v) { if (!o.has(v)) r.add(v); }); return r; };
        if (!sp.symmetricDifference) sp.symmetricDifference = function (o) { var r = new Set(this); Array.from(o.keys ? o.keys() : o).forEach(function (v) { if (r.has(v)) r.delete(v); else r.add(v); }); return r; };
        if (!sp.isSubsetOf) sp.isSubsetOf = function (o) { return Array.from(this).every(function (v) { return o.has(v); }); };
        if (!sp.isSupersetOf) sp.isSupersetOf = function (o) { var self = this; return Array.from(o.keys ? o.keys() : o).every(function (v) { return self.has(v); }); };
        if (!sp.isDisjointFrom) sp.isDisjointFrom = function (o) { return !Array.from(this).some(function (v) { return o.has(v); }); };
        if (!window.requestIdleCallback) {
          window.requestIdleCallback = function (cb) { return setTimeout(function () { cb({ didTimeout: false, timeRemaining: function () { return 10; } }); }, 1); };
          window.cancelIdleCallback = function (id) { clearTimeout(id); };
        }
      } catch (e) { post('shim: ' + e); }
      window.addEventListener('error', function (e) {
        post((e.message || 'error') + ' @ ' + (e.filename || '') + ':' + (e.lineno || 0) + ' [' + location.href + ']');
      });
      window.addEventListener('unhandledrejection', function (e) {
        var r = e.reason;
        post('promise: ' + (r && (r.stack || r.message) || r) + ' [' + location.href + ']');
      });
    })();
    """#
}
