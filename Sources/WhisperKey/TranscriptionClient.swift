import Foundation

/// Talks to the local faster-whisper server; starts it if it isn't running.
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
            completion(nil)
            return
        }
        try? FileManager.default.removeItem(at: wavURL)

        var req = URLRequest(url: baseURL.appendingPathComponent("transcribe"))
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 120

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { NSLog("Transcribe request failed: \(err)") }
            guard let data,
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                completion(nil)
                return
            }
            completion(text)
        }.resume()
    }
}
