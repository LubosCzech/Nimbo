import AppKit
import SwiftUI
import WebKit

struct WebLookupSheet: View {
    let lookup: WebLookup
    @Environment(\.dismiss) private var dismiss
    @State private var searchMode: GoogleSearchMode = .ai

    private var currentURL: URL { lookup.searchURL(for: searchMode) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(CleanerTheme.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lookup.title).font(.headline).lineLimit(1)
                    Text(lookup.context).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(currentURL)
                } label: {
                    Label("Otevřít v prohlížeči", systemImage: "safari")
                }
                Button("Zavřít") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)

            Divider()

            HStack {
                Picker("Typ výsledku", selection: $searchMode) {
                    ForEach(GoogleSearchMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 245)
                Spacer()
                if searchMode == .ai {
                    Label("Požadavek na AI • výsledek určuje Google", systemImage: "info.circle")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(lookup.query).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("Google relace se pamatuje").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)

            if searchMode == .ai {
                HStack {
                    Text("Pokud Google vrátí běžné výsledky, otevřete AI Mode v prohlížeči.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Google AI Mode") {
                        NSWorkspace.shared.open(URL(string: "https://www.google.com/ai")!)
                    }
                    Button("Kopírovat dotaz") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lookup.query, forType: .string)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            GoogleResultsView(url: currentURL)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 620)
        .tint(CleanerTheme.mint)
    }
}

private struct GoogleResultsView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // WKWebView's default UA lacks Safari's Version/Safari tokens. Google
        // can serve its legacy search interface to that otherwise modern engine.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        webView.allowsMagnification = true
        context.coordinator.requestedURL = url
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.requestedURL != url else { return }
        context.coordinator.requestedURL = url
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var requestedURL: URL?

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased(),
                  scheme == "https" || scheme == "about" else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
