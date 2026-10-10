import Flutter
import SwiftUI
import Translation
import UIKit

/// On-device recipe translation via Apple's Translation framework (iOS 18+).
///
/// Channel `com.pixelstomacros/translation`:
///  - `status(from,to)`        → "installed" | "supported" | "unsupported"
///  - `prepare(from,to)`       → Bool. Shows Apple's language-download prompt
///                               (via a hidden SwiftUI `.translationTask` host).
///  - `translateBatch(from,to,strings)` → [String] in the same order.
///    iOS 26+: `TranslationSession(installedSource:target:)`;
///    iOS 18–25: session obtained from the hidden `.translationTask` host.
final class TranslationPlugin {
    static let channelName = "com.pixelstomacros/translation"

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any] ?? [:]
            guard let from = args["from"] as? String, let to = args["to"] as? String else {
                result(FlutterError(code: "bad_args", message: "from/to are required", details: nil))
                return
            }
            let source = Locale.Language(identifier: from)
            let target = Locale.Language(identifier: to)
            switch call.method {
            case "status":
                Task { @MainActor in
                    result(await status(source: source, target: target))
                }
            case "prepare":
                Task { @MainActor in
                    result(await prepare(source: source, target: target))
                }
            case "translateBatch":
                let strings = args["strings"] as? [String] ?? []
                Task { @MainActor in
                    if let out = await translate(strings, source: source, target: target) {
                        result(out)
                    } else {
                        result(FlutterError(code: "translate_failed", message: "Translation failed", details: nil))
                    }
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    @MainActor
    private static func status(source: Locale.Language, target: Locale.Language) async -> String {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: return "installed"
        case .supported: return "supported"
        case .unsupported: return "unsupported"
        @unknown default: return "unsupported"
        }
    }

    @MainActor
    private static func prepare(source: Locale.Language, target: Locale.Language) async -> Bool {
        // Generous timeout: the user may take a while to accept the system
        // download sheet and the download itself can take minutes.
        let ok: Bool? = await TranslationHostRun<Bool>.run(
            source: source, target: target, timeout: 600
        ) { session in
            try await session.prepareTranslation()
            return true
        }
        NSLog("[TranslationPlugin] prepare \(source.minimalIdentifier)>\(target.minimalIdentifier) ok=\(ok ?? false)")
        return ok ?? false
    }

    @MainActor
    private static func translate(
        _ strings: [String], source: Locale.Language, target: Locale.Language
    ) async -> [String]? {
        if strings.isEmpty { return [] }
        if #available(iOS 26.0, *) {
            let session = TranslationSession(installedSource: source, target: target)
            do {
                return try await translate(strings, with: session)
            } catch {
                NSLog("[TranslationPlugin] installedSource session failed: \(error) — falling back to host")
            }
        }
        return await TranslationHostRun<[String]>.run(
            source: source, target: target, timeout: 90
        ) { session in
            try await translate(strings, with: session)
        }
    }

    private static func translate(_ strings: [String], with session: TranslationSession) async throws -> [String] {
        let requests = strings.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)
        var out = strings
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id), out.indices.contains(index) {
                out[index] = response.targetText
            }
        }
        return out
    }
}

/// Invisible SwiftUI view whose only job is to obtain a `TranslationSession`
/// through `.translationTask` (the iOS 18 API; it also presents Apple's
/// language-download prompt when needed).
private struct TranslationHostView: View {
    let configuration: TranslationSession.Configuration
    let action: (TranslationSession) async -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                await action(session)
            }
    }
}

/// One-shot hidden host: attaches a 1×1 UIHostingController to the top-most
/// view controller, runs `body` with the session, then detaches. The result is
/// delivered exactly once (nil on error or timeout).
@MainActor
private final class TranslationHostRun<T> {
    private var continuation: CheckedContinuation<T?, Never>?
    private var host: UIViewController?

    static func run(
        source: Locale.Language,
        target: Locale.Language,
        timeout: TimeInterval,
        body: @escaping (TranslationSession) async throws -> T
    ) async -> T? {
        guard let parent = topViewController() else {
            NSLog("[TranslationPlugin] no view controller to host translation session")
            return nil
        }
        let run = TranslationHostRun<T>()
        return await withCheckedContinuation { continuation in
            run.continuation = continuation
            let view = TranslationHostView(
                configuration: TranslationSession.Configuration(source: source, target: target)
            ) { session in
                do {
                    let value = try await body(session)
                    await MainActor.run { run.finish(value) }
                } catch {
                    NSLog("[TranslationPlugin] session task failed: \(error)")
                    await MainActor.run { run.finish(nil) }
                }
            }
            let host = UIHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            parent.addChild(host)
            parent.view.addSubview(host.view)
            host.didMove(toParent: parent)
            run.host = host
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak run] in
                run?.finish(nil)
            }
        }
    }

    private func finish(_ value: T?) {
        guard let continuation else { return }
        self.continuation = nil
        if let host {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            self.host = nil
        }
        continuation.resume(returning: value)
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow }
            ?? windows.first
            ?? (UIApplication.shared.delegate as? AppDelegate)?.window
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
