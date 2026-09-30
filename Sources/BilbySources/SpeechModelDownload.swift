import Foundation

/// Streams bounded chunks; URLSession's temporary-file downloader would only
/// let us reject an oversized response after it had already filled the disk.
final class SpeechModelDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let expected: Int64
    private let receive: PinnedSpeechModel.Receive
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancelled = false
    private var failure: Error?

    init(expected: Int64, receive: @escaping PinnedSpeechModel.Receive) {
        self.expected = expected
        self.receive = receive
    }

    static func fetch(_ url: URL, _ expected: Int64, _ receive: @escaping PinnedSpeechModel.Receive) async throws {
        guard allowed(url) else { throw SpeechModelError.download }
        let delegate = SpeechModelDownload(expected: expected, receive: receive)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(session: session, url: url, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
            let host = url.host?.lowercased()
        else { return false }
        return host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host.hasSuffix(".hf.co")
    }

    private func start(session: URLSession, url: URL, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        var request = URLRequest(url: url)
        // Keep advertised lengths comparable with the manifest's raw bytes.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    private func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            response.expectedContentLength == -1 || response.expectedContentLength == expected
        else {
            failure = SpeechModelError.download
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { try receive(data) } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        if cancelled {
            continuation.resume(throwing: CancellationError())
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if error != nil {
            continuation.resume(throwing: SpeechModelError.download)
        } else {
            continuation.resume()
        }
    }
}
