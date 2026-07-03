//  Analytics.swift
//  AudioSpectrumPro
//
//  Anonymous, self-hosted usage analytics via Umami (umami.croscor.com).
//  No device identifiers, no IDFA, no personal data, no audio — Umami derives
//  an anonymous, daily-rotating visitor hash server-side from IP + User-Agent.
//  We only send which screens/features are used. Fire-and-forget, off the main
//  thread, and a silent no-op when the user opts out or the network fails.

import Foundation
import UIKit

final class Analytics {
    static let shared = Analytics()

    private let endpoint  = URL(string: "https://umami.croscor.com/api/send")!
    private let websiteID = "d35bdf89-edfa-47e9-8098-291993fa2cf1"
    // Synthetic hostname so app traffic is separable from the marketing website
    // (audiospectrum.croscor.com) inside the same Umami dashboard.
    private let hostname  = "audiospectrum.app"
    static let optOutKey  = "analytics_opt_out"

    private let session: URLSession
    private let userAgent: String
    private let screenSize: String
    /// Umami cache token from the last successful send — replayed via the
    /// `x-umami-cache` header so the server can skip session re-resolution.
    private var cacheToken: String?
    /// Path of the current screen; events attach to it as their `url`.
    private var currentPath = "/"
    private let queue = DispatchQueue(label: "analytics.umami", qos: .utility)

    var isOptedOut: Bool {
        UserDefaults.standard.bool(forKey: Analytics.optOutKey)
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)

        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        // Must read as a real iOS client — Umami silently drops bot-like UAs
        // (verified: a plain "App/1.2 (iOS)" UA is rejected as a bot).
        let os = ProcessInfo.processInfo.operatingSystemVersion
        userAgent = "AudioSpectrumPro/\(ver) (iPhone; CPU iPhone OS \(os.majorVersion)_\(os.minorVersion) like Mac OS X) Mobile"

        let b = UIScreen.main.nativeBounds
        screenSize = "\(Int(b.width))x\(Int(b.height))"
    }

    // MARK: - Public API

    /// Record a screen view and make it the current page for later events.
    /// `path` is a leading-slash route, e.g. "/spectrum".
    func screen(_ path: String) {
        currentPath = path
        send(url: path, name: nil, data: nil)
    }

    /// Record a named event on the current screen with optional string data.
    func event(_ name: String, _ data: [String: String]? = nil) {
        send(url: currentPath, name: name, data: data)
    }

    // MARK: - Transport

    private func send(url: String, name: String?, data: [String: String]?) {
        guard !isOptedOut else { return }
        queue.async { [weak self] in
            guard let self else { return }

            var payload: [String: Any] = [
                "website":  self.websiteID,
                "hostname": self.hostname,
                "screen":   self.screenSize,
                "language": Locale.preferredLanguages.first ?? "en",
                "url":      url,
            ]
            if let name { payload["name"] = name }
            if let data { payload["data"] = data }

            guard let httpBody = try? JSONSerialization.data(
                withJSONObject: ["type": "event", "payload": payload]
            ) else { return }

            var req = URLRequest(url: self.endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
            if let token = self.cacheToken {
                req.setValue(token, forHTTPHeaderField: "x-umami-cache")
            }
            req.httpBody = httpBody

            self.session.dataTask(with: req) { [weak self] respData, _, _ in
                guard let self, let respData,
                      let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                      let token = obj["cache"] as? String else { return }
                self.queue.async { self.cacheToken = token }
            }.resume()
        }
    }
}
