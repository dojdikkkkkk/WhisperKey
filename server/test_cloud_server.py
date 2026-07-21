import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import wave
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


@contextmanager
def mock_provider():
    requests = []
    response = json.dumps({"text": "cloud result", "language": "en"}).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            requests.append({"authorization": self.headers.get("Authorization"),
                             "body": self.rfile.read(length)})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)

        def log_message(self, _format, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/v1/audio/transcriptions", requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wav_bytes(sample):
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(int(sample).to_bytes(2, "little", signed=True) * 1600)
    return output.getvalue()


def wait_for_health(port, process):
    url = f"http://127.0.0.1:{port}/health"
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError("cloud server exited during startup")
        try:
            with urlopen(url, timeout=0.2) as response:
                return json.load(response)
        except (URLError, TimeoutError):
            time.sleep(0.05)
    raise AssertionError("cloud server did not become healthy")


class CloudServerTests(unittest.TestCase):
    def test_cloud_mode_skips_mlx_and_preserves_local_api(self):
        server_script = Path(__file__).with_name("transcribe_server.py")
        with mock_provider() as (endpoint, provider_requests), tempfile.TemporaryDirectory() as home:
            port = free_port()
            config_dir = Path(home) / ".whisperkey"
            config_dir.mkdir()
            (config_dir / "config.json").write_text(json.dumps({
                "port": port,
                "transcriptionBackend": "openai",
                "cloudEndpoint": endpoint,
                "cloudModel": "test-model",
                "logTranscripts": False,
            }))
            env = dict(os.environ, HOME=home, PYTHONDONTWRITEBYTECODE="1")
            process = subprocess.Popen(
                [sys.executable, str(server_script)],
                cwd=server_script.parent,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            output = ""
            try:
                health = wait_for_health(port, process)
                self.assertEqual(health["status"], "ok")
                self.assertEqual(health["backend"], "openai")
                self.assertEqual(health["model"], "test-model")

                silent_request = Request(
                    f"http://127.0.0.1:{port}/transcribe",
                    data=wav_bytes(0), method="POST",
                    headers={"Content-Type": "audio/wav", "X-WhisperKey-API-Key": "test-key"},
                )
                with urlopen(silent_request, timeout=2) as response:
                    self.assertEqual(json.load(response)["text"], "")
                self.assertEqual(provider_requests, [])

                request = Request(
                    f"http://127.0.0.1:{port}/transcribe",
                    data=wav_bytes(1000), method="POST",
                    headers={"Content-Type": "audio/wav", "X-WhisperKey-API-Key": "test-key"},
                )
                with urlopen(request, timeout=2) as response:
                    result = json.load(response)
                self.assertEqual(result["text"], "cloud result")
                self.assertEqual(result["language"], "en")
                self.assertEqual(provider_requests[0]["authorization"], "Bearer test-key")
            finally:
                process.terminate()
                try:
                    output, _ = process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    output, _ = process.communicate()

        self.assertIn("Cloud STT ready: test-model", output)
        self.assertNotIn("Warming up", output)
        self.assertNotIn("test-key", output)

    def test_local_mode_still_warms_configured_model(self):
        server_script = Path(__file__).with_name("transcribe_server.py")
        with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as modules:
            port = free_port()
            config_dir = Path(home) / ".whisperkey"
            config_dir.mkdir()
            (config_dir / "config.json").write_text(json.dumps({
                "port": port,
                "transcriptionBackend": "local",
                "model": "test-local-model",
                "logTranscripts": False,
            }))
            Path(modules, "mlx_whisper.py").write_text(
                "def transcribe(audio, path_or_hf_repo=None, **kwargs):\n"
                "    return {'text': 'local result', 'language': 'en'}\n"
            )
            Path(modules, "numpy.py").write_text(
                "float32 = 'float32'\n"
                "def zeros(size, dtype=None): return [0.0] * size\n"
            )
            env = dict(os.environ, HOME=home, PYTHONDONTWRITEBYTECODE="1",
                       PYTHONPATH=modules)
            process = subprocess.Popen(
                [sys.executable, str(server_script)],
                cwd=server_script.parent,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                health = wait_for_health(port, process)
                deadline = time.time() + 2
                while health["status"] == "loading" and time.time() < deadline:
                    time.sleep(0.05)
                    health = wait_for_health(port, process)
                self.assertEqual(health["status"], "ok")
                self.assertEqual(health["backend"], "local")
                self.assertEqual(health["model"], "test-local-model")
            finally:
                process.terminate()
                try:
                    output, _ = process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    output, _ = process.communicate()

        self.assertIn("Warming up test-local-model", output)
        self.assertIn("Model warm", output)


if __name__ == "__main__":
    unittest.main()
