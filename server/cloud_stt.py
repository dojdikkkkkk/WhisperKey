"""OpenAI-compatible cloud speech-to-text client."""

import json
import re
import socket
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

MAX_RESPONSE_BYTES = 1024 * 1024
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}


class CloudSTTError(Exception):
    """A safe, user-facing cloud transcription failure."""


def _origin(url):
    parsed = urlsplit(url)
    try:
        port = parsed.port
    except ValueError as error:
        raise CloudSTTError("Cloud endpoint has an invalid port") from error
    if port is None:
        port = 443 if parsed.scheme.lower() == "https" else 80
    return parsed.scheme.lower(), (parsed.hostname or "").lower(), port


def validate_endpoint(endpoint):
    try:
        parsed = urlsplit(endpoint)
        origin = _origin(endpoint)
    except (TypeError, ValueError) as error:
        raise CloudSTTError("Cloud endpoint is not a valid URL") from error
    scheme, host, _ = origin
    if scheme not in {"http", "https"} or not host or not parsed.path:
        raise CloudSTTError("Cloud endpoint must be a full HTTP(S) URL")
    if parsed.username or parsed.password:
        raise CloudSTTError("Cloud endpoint must not contain credentials")
    if parsed.fragment:
        raise CloudSTTError("Cloud endpoint must not contain a URL fragment")
    if scheme == "http" and host not in LOOPBACK_HOSTS:
        raise CloudSTTError("Cloud endpoint must use HTTPS unless it is loopback")


class _SafeRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        resolved = urljoin(req.full_url, newurl)
        if _origin(req.full_url) != _origin(resolved):
            raise CloudSTTError("Cloud endpoint redirected to a different origin")
        return super().redirect_request(req, fp, code, msg, headers, resolved)


def _multipart_body(model, wav_data, prompt):
    boundary = "WhisperKey-" + uuid.uuid4().hex
    chunks = []

    def field(name, value):
        chunks.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            value.encode("utf-8"),
            b"\r\n",
        ])

    field("model", model)
    if prompt:
        field("prompt", prompt)
    chunks.extend([
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="file"; filename="recording.wav"\r\n',
        b"Content-Type: audio/wav\r\n\r\n",
        wav_data,
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def _sanitize_text(detail, api_key):
    if not isinstance(detail, str):
        return ""
    if api_key:
        detail = detail.replace(api_key, "[redacted]")
    detail = re.sub(r"[\x00-\x1f\x7f]+", " ", detail).strip()
    return detail[:300]


def _safe_detail(body, api_key):
    detail = ""
    try:
        payload = json.loads(body.decode("utf-8"))
        error = payload.get("error", "") if isinstance(payload, dict) else ""
        if isinstance(error, dict):
            detail = error.get("message", "")
        elif isinstance(error, str):
            detail = error
    except (UnicodeDecodeError, json.JSONDecodeError):
        pass
    return _sanitize_text(detail, api_key)


def _read_limited(response):
    body = response.read(MAX_RESPONSE_BYTES + 1)
    if len(body) > MAX_RESPONSE_BYTES:
        raise CloudSTTError("Cloud provider response is too large")
    return body


def transcribe(endpoint, model, api_key, wav_data, prompt="", timeout=110):
    """Transcribe WAV bytes through an OpenAI-compatible endpoint."""
    validate_endpoint(endpoint)
    model = model.strip() if isinstance(model, str) else ""
    api_key = api_key.strip() if isinstance(api_key, str) else ""
    if not model:
        raise CloudSTTError("Cloud model is not configured")
    if not api_key:
        raise CloudSTTError("Cloud API key is missing")

    body, content_type = _multipart_body(model, wav_data, prompt)
    request = Request(endpoint, data=body, method="POST", headers={
        "Accept": "application/json",
        "Authorization": f"Bearer {api_key}",
        "Content-Type": content_type,
        "User-Agent": "WhisperKey/1.0",
    })
    opener = build_opener(_SafeRedirectHandler())
    try:
        with opener.open(request, timeout=timeout) as response:
            response_body = _read_limited(response)
    except CloudSTTError:
        raise
    except HTTPError as error:
        try:
            error_body = error.read(MAX_RESPONSE_BYTES + 1)
        finally:
            error.close()
        detail = _safe_detail(error_body[:MAX_RESPONSE_BYTES], api_key)
        suffix = f": {detail}" if detail else ""
        raise CloudSTTError(f"Cloud provider returned HTTP {error.code}{suffix}") from None
    except (URLError, TimeoutError, socket.timeout) as error:
        detail = _sanitize_text(str(getattr(error, "reason", error)), api_key)
        suffix = f": {detail}" if detail else ""
        raise CloudSTTError(f"Cloud provider request failed{suffix}") from None

    try:
        payload = json.loads(response_body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise CloudSTTError("Cloud provider returned invalid JSON") from None
    if not isinstance(payload, dict) or not isinstance(payload.get("text"), str):
        raise CloudSTTError("Cloud provider response is missing text")
    language = payload.get("language", "")
    if not isinstance(language, str):
        language = ""
    return {"text": payload["text"], "language": language}
