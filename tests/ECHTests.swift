import Foundation

@main struct ECHTests {
    static func main() async throws {
        precondition(MirrorRouting.echAvailable)
        let routing = MirrorRouting()
        try routing.configure(ConnectionSettings(mode: .encrypted), persistChanges: false)
        let apiURL = URL(string: "https://api.bgm.tv/v0/subjects/8")!
        let candidates = routing.candidates(for: apiURL, credentials: true)
        precondition(candidates.count == 1 && candidates.allSatisfy { MirrorRouting.isECHHost($0.host) })
        precondition(routing.canonicalURL(for: candidates[0]) == apiURL)
        precondition(!MirrorRouting.isECHHost(routing.preferredURL(for: apiURL).host), "An external browser must never receive the internal ECH marker")
        precondition(MirrorRouting.echOrigin(for: URL(string: "https://api.bgm-tv.ech.invalid:444/a")!) == nil)
        precondition(MirrorRouting.echOrigin(for: URL(string: "https://evil.bgm-tv.ech.invalid/a")!) == nil)
        print("PASS: strict ECH mode has no ordinary or mirror fallback; credentials stay on authenticated official hosts")

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.bgm-tv.ech.invalid/a")!)
        request.httpMethod = "UNKNOWN"
        do {
            _ = try await ECHTransport.data(for: request, timeout: 1)
            preconditionFailure("Unsupported methods must fail closed")
        } catch let failure as ECHFailure { precondition(failure.code == "UNSUPPORTED_METHOD") }
        print("PASS: bridge rejects unsupported requests instead of using a plain connection")

        if CommandLine.arguments.contains("--live") {
            let cancellation = Task {
                let request = URLRequest(url: URL(string: "https://api.bgm-tv.ech.invalid/v0/subjects/8")!)
                return try await ECHTransport.data(for: request, timeout: 30)
            }
            try await Task.sleep(for: .milliseconds(30))
            let cancelledAt = Date()
            cancellation.cancel()
            do { _ = try await cancellation.value; preconditionFailure("Cancelled ECH request returned a response") }
            catch let error as URLError { precondition(error.code == .cancelled) }
            catch is CancellationError { }
            precondition(Date().timeIntervalSince(cancelledAt) < 2)
            precondition(ECHTransport.info?.activeRequests == 0)
            print("PASS: Swift cancellation reaches the embedded HTTP request and releases its context")

            for host in ["api.bgm-tv.ech.invalid", "bgm-tv.ech.invalid", "lain.bgm-tv.ech.invalid"] {
                var request = URLRequest(url: URL(string: "https://\(host)/cdn-cgi/trace")!)
                request.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await ConnectionTransport.data(for: request, session: session, timeout: 18)
                let trace = String(decoding: data, as: UTF8.self).split(separator: "\n")
                precondition((response as? HTTPURLResponse)?.statusCode == 200)
                precondition(trace.contains("sni=encrypted"), "A successful HTTP response alone is insufficient evidence")
                let country = trace.first { $0.hasPrefix("loc=") } ?? "loc=unknown"
                print("PASS live: \(response.url!.host!) \(country) sni=encrypted")
            }
            let api = APIClient(session: session, routing: routing, discoverMirrors: false)
            let subject: Subject = try await api.get("/v0/subjects/8", as: Subject.self, force: true)
            precondition(subject.id == 8)
            let page = try await api.rawHTML(URL(string: "https://bgm.tv/subject/8")!, cacheKey: "ech-test-subject", force: true)
            precondition(page.contains("subject_inner_info") || page.contains("headerSubject"))
            let loader = ImageLoader(routing: routing)
            let cover = await loader.checkConnection(subject.heroURL!)
            precondition(cover)
            precondition(ConnectionService.allCases.allSatisfy { service in routing.diagnostics.first { $0.service == service }?.encrypted == true })
            let info = ECHTransport.info!
            precondition(info.proxyDisabled && info.acceptedConnections >= 3)
            precondition(info.directInterface.hasPrefix("en") || info.directInterface.hasPrefix("pdp_ip"))
            print("PASS live: real subject, HTML and decoded cover; accepted=\(info.acceptedConnections), physicalInterface=\(info.directInterface), proxyDisabled=true")
        }
    }
}
