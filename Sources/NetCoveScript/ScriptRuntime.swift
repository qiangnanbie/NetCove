//
//  ScriptRuntime.swift
//  模块运行时：JSContext + 双向异步桥（Promise ↔ Swift async/await）。
//  出网一律走宿主桥（白名单 + 限流），脚本不能直接触碰网络。
//

import Foundation
import JavaScriptCore
import Combine

@MainActor
final class ScriptRuntime: ObservableObject {

    enum State: Equatable {
        case idle
        case loading(String)
        case ready(moduleID: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastException: String?

    private let context: JSContext
    private let bridge: ScriptHTTPBridging
    private let policy: ScriptSandboxPolicy
    private let log: ScriptDebugLogStore
    private let namespace: String
    private var manifest: RexModManifest?

    init(namespace: String, bridge: ScriptHTTPBridging,
         policy: ScriptSandboxPolicy, log: ScriptDebugLogStore) {
        self.namespace = namespace
        self.bridge = bridge
        self.policy = policy
        self.log = log
        self.context = JSContext()!
        installBootstrap()
    }

    // MARK: - 加载

    func load(module manifest: RexModManifest, directory: URL) {
        state = .loading(manifest.id)
        self.manifest = manifest
        do {
            let scriptURL = directory.appendingPathComponent(manifest.entry)
            let source = try String(contentsOf: scriptURL, encoding: .utf8)
            context.evaluateScript(source, withSourceURL: scriptURL)
            if let exception = context.exception {
                state = .failed(exception.toString() ?? "script error")
                return
            }
            state = .ready(moduleID: manifest.id)
            log.append("module \(manifest.id) loaded")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func unload() {
        manifest = nil
        state = .idle
    }

    // MARK: - 调用

    /// 调用模块导出的全局函数（如 onDiscover），返回值自动 await Promise
    func call(_ function: String, argument: [String: Any] = [:]) async throws -> Any? {
        guard let fn = context.objectForKeyedSubscript(function),
              !fn.isUndefined else {
            throw ScriptError.functionMissing(function)
        }
        guard let result = fn.call(withArguments: [argument]) else {
            throw ScriptError.callFailed(context.exception?.toString() ?? "unknown")
        }
        return try await resolve(result)
    }

    private func resolve(_ value: JSValue) async throws -> Any? {
        if value.isUndefined { return nil }
        if value.isNull { return nil }

        // thenable?
        if let then = value.objectForKeyedSubscript("then"), !then.isUndefined {
            return try await withCheckedThrowingContinuation { continuation in
                let onFulfilled: @convention(block) (JSValue) -> Void = { resolved in
                    continuation.resume(returning: resolved.toObject())
                }
                let onRejected: @convention(block) (JSValue) -> Void = { error in
                    continuation.resume(throwing: ScriptError.callFailed(error.toString() ?? "rejected"))
                }
                _ = then.call(withArguments: [
                    JSValue(object: onFulfilled, in: context) as Any,
                    JSValue(object: onRejected, in: context) as Any
                ])
            }
        }
        return value.toObject()
    }

    // MARK: - 引导：把 netcove.* 注入 JS

    private func installBootstrap() {
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "unknown"
            self?.lastException = message
            self?.log.append("JS exception: \(message)")
        }

        let logBlock: @convention(block) (String) -> Void = { [weak self] message in
            self?.log.append("[js] \(message)")
        }
        context.setObject(logBlock, forKeyedSubscript: "__netcoveLog" as NSString)

        let storageGet: @convention(block) (String) -> String? = { [weak self] key in
            guard let self else { return nil }
            return UserDefaults.standard.string(forKey: "netcove.mod.\(self.namespace).\(key)")
        }
        context.setObject(storageGet, forKeyedSubscript: "__netcoveStorageGet" as NSString)

        let storageSet: @convention(block) (String, String) -> Void = { [weak self] key, value in
            guard let self else { return }
            UserDefaults.standard.set(value, forKey: "netcove.mod.\(self.namespace).\(key)")
        }
        context.setObject(storageSet, forKeyedSubscript: "__netcoveStorageSet" as NSString)

        // 出网：Swift 侧异步执行，完成后回调 JS 的 resolve/reject
        let fetchBlock: @convention(block) (String, String, String) -> Void = { [weak self] id, urlString, initJSON in
            guard let self else { return }
            Task { @MainActor in
                await self.performFetch(id: id, urlString: urlString, initJSON: initJSON)
            }
        }
        context.setObject(fetchBlock, forKeyedSubscript: "__netcoveFetch" as NSString)

        context.evaluateScript(Self.bootstrapScript)
    }

    private func performFetch(id: String, urlString: String, initJSON: String) async {
        guard let url = URL(string: urlString) else {
            reject(id: id, message: "invalid url")
            return
        }
        var request = ScriptHTTPRequest(url: url, method: "GET", headers: [:], body: nil)
        if let data = initJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let method = parsed["method"] as? String { request.method = method.uppercased() }
            if let headers = parsed["headers"] as? [String: String] { request.headers = headers }
            if let body = parsed["body"] as? String { request.body = Data(body.utf8) }
        }

        do {
            let response = try await bridge.fetch(request)
            let body = String(data: response.body, encoding: .utf8) ?? ""
            let payload: [String: Any] = ["status": response.status,
                                          "headers": response.headers,
                                          "body": body]
            resolve(id: id, payload: payload)
        } catch {
            reject(id: id, message: error.localizedDescription)
        }
    }

    private func resolve(id: String, payload: [String: Any]) {
        guard let fn = context.objectForKeyedSubscript("__netcoveResolve") else { return }
        _ = fn.call(withArguments: [id, payload])
    }

    private func reject(id: String, message: String) {
        guard let fn = context.objectForKeyedSubscript("__netcoveReject") else { return }
        _ = fn.call(withArguments: [id, message])
    }

    static let bootstrapScript = """
    (function () {
      var pending = {};
      var seq = 0;
      globalThis.__netcoveResolve = function (id, payload) {
        var entry = pending[id];
        if (!entry) return;
        delete pending[id];
        entry.resolve(payload);
      };
      globalThis.__netcoveReject = function (id, message) {
        var entry = pending[id];
        if (!entry) return;
        delete pending[id];
        entry.reject(new Error(message));
      };
      globalThis.netcove = {
        log: function () {
          __netcoveLog(Array.prototype.slice.call(arguments).map(String).join(' '));
        },
        fetch: function (url, init) {
          return new Promise(function (resolve, reject) {
            var id = String(++seq);
            pending[id] = { resolve: resolve, reject: reject };
            __netcoveFetch(id, String(url), JSON.stringify(init || {}));
          });
        },
        storage: {
          get: function (key) { return __netcoveStorageGet(String(key)); },
          set: function (key, value) { __netcoveStorageSet(String(key), String(value)); }
        }
      };
    })();
    """
}

extension ScriptError {
    static func functionMissing(_ name: String) -> ScriptError {
        .callFailed("module doesn't export \(name)")
    }
}
