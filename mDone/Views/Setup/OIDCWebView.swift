import SwiftUI
import WebKit

#if os(iOS)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#elseif os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

struct OIDCWebView: PlatformViewRepresentable {
    let url: URL
    let redirectURI: String
    let onCallback: (String) -> Void
    let onCancel: () -> Void

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #elseif os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        #if os(iOS)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #elseif os(macOS)
        webView.autoresizesSubviews = true
        webView.autoresizingMask = [.width, .height]
        #endif

        #if DEBUG
        print("[mDone] WebView initiating load for: \(self.url.absoluteString)")
        #endif
        
        let request = URLRequest(url: self.url)
        webView.load(request)
        
        return webView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OIDCWebView

        init(_ parent: OIDCWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                #if DEBUG
                print("[mDone] WebView navigating to: \(url.absoluteString)")
                #endif

                if url.absoluteString.hasPrefix(parent.redirectURI) {
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let queryItems = components.queryItems,
                       let code = queryItems.first(where: { $0.name == "code" })?.value {
                        #if DEBUG
                        print("[mDone] Intercepted OAuth code: \(code)")
                        #endif
                        parent.onCallback(code)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            #if DEBUG
            print("[mDone] WebView didStartProvisionalNavigation: \(webView.url?.absoluteString ?? "no URL")")
            #endif
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if DEBUG
            print("[mDone] WebView didFinish: \(webView.url?.absoluteString ?? "no URL")")
            #endif
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("[mDone] WebView didFail: \(error.localizedDescription)")
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("[mDone] WebView didFailProvisionalNavigation: \(error.localizedDescription)")
            #endif
        }
    }
}
