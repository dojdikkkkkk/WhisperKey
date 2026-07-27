import json
import socket
import threading
import unittest
from contextlib import contextmanager
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cloud_stt import CloudSTTError, transcribe


@contextmanager
def provider(status=200, payload=None, location=None):
    requests = []
    response = payload if isinstance(payload, bytes) else json.dumps(
        payload if payload is not None else {"text": "hello", "language": "en"}
    ).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            requests.append({"headers": self.headers, "body": self.rfile.read(length)})
            self.send_response(status)
            if location:
                self.send_header("Location", location)
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
        yield f"http://127.0.0.1:{server.server_port}/audio/transcriptions", requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def multipart_parts(record):
    raw = (
        f"Content-Type: {record['headers']['Content-Type']}\r\n"
        "MIME-Version: 1.0\r\n\r\n"
    ).encode() + record["body"]
    message = BytesParser(policy=default).parsebytes(raw)
    parts = {}
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        parts[name] = {
            "filename": part.get_filename(),
            "content_type": part.get_content_type(),
            "value": part.get_payload(decode=True),
        }
    return parts


class CloudSTTTests(unittest.TestCase):
    def test_sends_openai_compatible_multipart_request(self):
        with provider(payload={"text": "hello", "language": "en"}) as (endpoint, requests):
            result = transcribe(
                endpoint=endpoint,
                model="whisper-large-v3-turbo",
                api_key="test-key",
                wav_data=b"RIFF-test-wave",
                prompt="Glossary: WhisperKey.",
            )

        self.assertEqual(result, {"text": "hello", "language": "en"})
        self.assertEqual(requests[0]["headers"]["Authorization"], "Bearer test-key")
        parts = multipart_parts(requests[0])
        self.assertEqual(parts["model"]["value"], b"whisper-large-v3-turbo")
        self.assertEqual(parts["prompt"]["value"], b"Glossary: WhisperKey.")
        self.assertEqual(parts["file"]["filename"], "recording.wav")
        self.assertEqual(parts["file"]["content_type"], "audio/wav")
        self.assertEqual(parts["file"]["value"], b"RIFF-test-wave")

    def test_omits_empty_prompt_and_accepts_missing_language(self):
        with provider(payload={"text": "hello"}) as (endpoint, requests):
            result = transcribe(endpoint, "model", "test-key", b"wav", prompt="")

        self.assertEqual(result, {"text": "hello", "language": ""})
        self.assertNotIn("prompt", multipart_parts(requests[0]))

    def test_rejects_cleartext_remote_endpoint(self):
        with self.assertRaisesRegex(CloudSTTError, "HTTPS"):
            transcribe("http://example.com/v1/audio/transcriptions", "model", "key", b"wav")

    def test_rejects_cross_origin_redirect_without_forwarding_key(self):
        with provider() as (target, target_requests):
            with provider(status=302, location=target) as (source, _):
                with self.assertRaisesRegex(CloudSTTError, "different origin"):
                    transcribe(source, "model", "test-key", b"wav")
        self.assertEqual(target_requests, [])

    def test_sanitizes_network_failure_without_exposing_key(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            endpoint = f"http://127.0.0.1:{sock.getsockname()[1]}/audio/transcriptions"
        with self.assertRaises(CloudSTTError) as raised:
            transcribe(endpoint, "model", "test-key", b"wav", timeout=0.2)
        self.assertIn("request failed", str(raised.exception))
        self.assertNotIn("test-key", str(raised.exception))

    def test_sanitizes_openai_error_message_and_redacts_key(self):
        payload = {"error": {"message": "bad credential test-key\ntry another"}}
        with provider(status=401, payload=payload) as (endpoint, _):
            with self.assertRaises(CloudSTTError) as raised:
                transcribe(endpoint, "model", "test-key", b"wav")

        message = str(raised.exception)
        self.assertIn("HTTP 401", message)
        self.assertIn("[redacted]", message)
        self.assertNotIn("test-key", message)
        self.assertNotIn("\n", message)

    def test_rejects_malformed_or_incomplete_response(self):
        for payload in (b"not json", {"language": "en"}, {"text": 123}):
            with self.subTest(payload=payload):
                with provider(payload=payload) as (endpoint, _):
                    with self.assertRaises(CloudSTTError):
                        transcribe(endpoint, "model", "key", b"wav")


if __name__ == "__main__":
    unittest.main()
