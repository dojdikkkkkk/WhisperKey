import Foundation

/// Talks to the local transcription gateway; starts it if it isn't running.
final class TranscriptionClient {
    private var baseURL: URL { URL(string: "http://127.0.0.1:\(Config.shared.port)")! }
    private var serverDir: String { Config.shared.serverDir }

    func ensureServerRunning() {
        healthCheck { healthy in
            guard !healthy else { return }
            NSLog("Transcription server not responding — launching it")
            self.launchServer()
        }
    }

    private func healthCheck(completion: @escaping (Bool) -> Void) {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            completion((resp as? HTTPURLResponse)?.statusCode == 200)
        }.resume()
    }

    private func launchServer() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "\(serverDir)/venv/bin/python")
        proc.arguments = ["\(serverDir)/transcribe_server.py"]
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDir)
        do {
            try proc.run()
        } catch {
            NSLog("Failed to launch server: \(error)")
        }
    }

    func requestLearn() {
        var req = URLRequest(url: baseURL.appendingPathComponent("learn"))
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req).resume()
    }

    func transcribe(wavURL: URL, completion: @escaping (String?) -> Void) {
        guard let data = try? Data(contentsOf: wavURL) else {
            reportFailure("Could not read the recorded audio", cloud: false, completion: completion)
            return
        }
        try? FileManager.default.removeItem(at: wavURL)

        let config = Config.shared
        let cloud = config.transcriptionBackend == "openai"
        var apiKey: String?
        if cloud {
            do {
                apiKey = try CloudAPIKeyStore.load()
            } catch {
                reportFailure("Could not read the cloud API key from Keychain: \(error.localizedDescription)",
                              cloud: true, completion: completion)
                return
            }
            guard let apiKey, !apiKey.isEmpty else {
                reportFailure("Add a cloud API key in WhisperKey Settings",
                              cloud: true, completion: completion)
                return
            }
        }

        var req = URLRequest(url: baseURL.appendingPathComponent("transcribe"))
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        if let apiKey { req.setValue(apiKey, forHTTPHeaderField: "X-WhisperKey-API-Key") }
        req.httpBody = data
        req.timeoutInterval = 120

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err {
                self.reportFailure("Transcription server request failed: \(err.localizedDescription)",
                                   cloud: cloud, completion: completion)
                return
            }
            guard let response = resp as? HTTPURLResponse else {
                self.reportFailure("Transcription server returned no response",
                                   cloud: cloud, completion: completion)
                return
            }
            guard let data else {
                self.reportFailure("Transcription server returned an empty response",
                                   cloud: cloud, completion: completion)
                return
            }
            guard response.statusCode == 200 else {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let detail = json?["error"] as? String
                let message: String
                if let detail, !detail.isEmpty {
                    message = detail
                } else {
                    message = "Transcription server returned HTTP \(response.statusCode)"
                }
                self.reportFailure(message, cloud: cloud, completion: completion)
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                self.reportFailure("Transcription server returned an invalid response",
                                   cloud: cloud, completion: completion)
                return
            }
            completion(text)
        }.resume()
    }

    private func reportFailure(_ message: String, cloud: Bool,
                               completion: @escaping (String?) -> Void) {
        NSLog("Transcription failed: \(message)")
        debugLog("transcription failed: \(message)")
        if cloud { TranscriptionNotifier.postCloudFailure(message) }
        completion(nil)
    }
}
