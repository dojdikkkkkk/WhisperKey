#!/usr/bin/env python3
"""Grow the WhisperKey glossary from recent transcriptions.

Feeds the last transcriptions + current glossary to an LLM and merges any
newly proposed terms/rules back into glossary.json. The LLM backend is chosen
in ~/.whisperkey/config.json (key "learnBackend"):

  ollama        — local LLM via the Ollama HTTP API (default model qwen3:4b)
  claude        — Claude Code CLI (`claude -p`, haiku model)
  codex         — Codex CLI (`codex exec`)
  pi            — Pi CLI (`pi -p --no-session --no-tools`)
  agent-manual  — writes the task to learn_request.md for ANY coding agent
                  (Hermes, OpenClaw, ...) to fulfil by hand
  off           — disabled

Run manually, via POST /learn, or automatically every N transcriptions.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.expanduser("~/.whisperkey/config.json")
GLOSSARY_PATH = os.path.join(BASE_DIR, "glossary.json")
TRANSCRIPTS_PATH = os.path.join(BASE_DIR, "transcripts.jsonl")
REQUEST_PATH = os.path.join(BASE_DIR, "learn_request.md")
RECENT = 50
MAX_TERMS = 120  # keep initial_prompt effective

PROMPT_TEMPLATE = """You maintain the auto-correction glossary of a Whisper-based dictation system.
The user dictates in their language, mixing in domain terms (product names, domains, tools)
that Whisper tends to mangle.

Current glossary (glossary.json):
{glossary}

Recent transcriptions ("raw" = before correction, "text" = after):
{transcripts}

Find domain terms in the transcriptions that Whisper likely mangled and that the
glossary does not cover yet: transliterated English words (e.g. "гитхаб" -> GitHub),
the word for "dot" instead of "." in domain names, split or distorted product and
organization names. Do NOT touch ordinary speech or words that could be regular words.
Write regex patterns conservatively: whole words only, no risk of false positives.

Reply ONLY with valid JSON, no explanations:
{{"new_terms": ["..."], "new_rules": [{{"canonical": "...", "pattern": "..."}}]}}
If there is nothing to add, return empty lists."""


def load_config():
    cfg = {"learnBackend": "off", "ollamaModel": "qwen3:4b"}
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    except (OSError, json.JSONDecodeError):
        pass
    return cfg


def find_cli(name, extra_paths=()):
    candidates = [shutil.which(name)]
    candidates += [os.path.expanduser(f"~/.local/bin/{name}"),
                   f"/opt/homebrew/bin/{name}", f"/usr/local/bin/{name}"]
    candidates += list(extra_paths)
    for c in candidates:
        if c and os.path.exists(c):
            return c
    return None


# --- backends: each takes the prompt, returns the raw LLM output string ------

def backend_ollama(prompt, cfg):
    payload = json.dumps({
        "model": cfg.get("ollamaModel", "qwen3:4b"),
        "prompt": prompt,
        "stream": False,
    }).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate", data=payload,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=240) as resp:
            return json.loads(resp.read())["response"]
    except OSError as e:
        raise RuntimeError(
            f"Ollama is not reachable at 127.0.0.1:11434 ({e}). "
            "Install it from https://ollama.com and run: "
            f"ollama pull {cfg.get('ollamaModel', 'qwen3:4b')}") from e


def backend_claude(prompt, cfg):
    cli = find_cli("claude")
    if not cli:
        raise RuntimeError("claude CLI not found — install Claude Code or switch learnBackend")
    r = subprocess.run([cli, "-p", prompt, "--model", "haiku", "--output-format", "text"],
                       capture_output=True, text=True, timeout=240)
    if r.returncode != 0:
        raise RuntimeError(f"claude failed: {r.stderr[-300:]}")
    return r.stdout


def backend_codex(prompt, cfg):
    cli = find_cli("codex")
    if not cli:
        raise RuntimeError("codex CLI not found — install Codex or switch learnBackend")
    r = subprocess.run([cli, "exec", prompt], capture_output=True, text=True, timeout=240)
    if r.returncode != 0:
        raise RuntimeError(f"codex failed: {r.stderr[-300:]}")
    return r.stdout


def backend_pi(prompt, cfg):
    cli = find_cli("pi", (os.path.expanduser("~/.npm-global/bin/pi"),))
    if not cli:
        raise RuntimeError("pi CLI not found — install Pi or switch learnBackend")
    r = subprocess.run(
        [cli, "-p", "--no-session", "--no-tools", prompt],
        capture_output=True, text=True, timeout=240,
    )
    if r.returncode != 0:
        raise RuntimeError(f"pi failed: {r.stderr[-300:]}")
    return r.stdout


def backend_agent_manual(prompt, cfg):
    """No LLM call: write the task to a file for the user's own coding agent."""
    instructions = (
        "# WhisperKey glossary learning task\n\n"
        "Give this file to your coding agent (Claude Code, Codex, Hermes, OpenClaw, ...).\n\n"
        "Agent: perform the task below, then merge the resulting JSON into\n"
        f"`{GLOSSARY_PATH}` — append `new_terms` to the `terms` array (dedup, keep it\n"
        "under 120 items) and `new_rules` objects to the `rules` array (dedup by\n"
        "`canonical`, validate each `pattern` compiles as a regex). The server\n"
        "hot-reloads the file — no restart needed.\n\n---\n\n" + prompt + "\n"
    )
    with open(REQUEST_PATH, "w", encoding="utf-8") as f:
        f.write(instructions)
    print(f"Task written to {REQUEST_PATH} — hand it to your agent.")
    return None  # nothing to merge automatically


BACKENDS = {
    "ollama": backend_ollama,
    "claude": backend_claude,
    "codex": backend_codex,
    "pi": backend_pi,
    "agent-manual": backend_agent_manual,
}


def main():
    cfg = load_config()
    backend_name = cfg.get("learnBackend", "off")
    if backend_name == "off":
        print("learning disabled (learnBackend=off)")
        return 0
    backend = BACKENDS.get(backend_name)
    if backend is None:
        print(f"unknown learnBackend: {backend_name}")
        return 1
    if not os.path.exists(TRANSCRIPTS_PATH):
        print("no transcripts yet")
        return 0

    with open(TRANSCRIPTS_PATH, encoding="utf-8") as f:
        lines = f.readlines()[-RECENT:]
    transcripts = "\n".join(line.strip() for line in lines)

    with open(GLOSSARY_PATH, encoding="utf-8") as f:
        glossary = json.load(f)

    prompt = PROMPT_TEMPLATE.format(
        glossary=json.dumps(glossary, ensure_ascii=False, indent=1),
        transcripts=transcripts,
    )

    try:
        output = backend(prompt, cfg)
    except RuntimeError as e:
        print(str(e))
        return 1
    if output is None:  # agent-manual
        return 0

    match = re.search(r"\{.*\}", output, re.DOTALL)
    if not match:
        print(f"no JSON in response: {output[-200:]}")
        return 1
    try:
        proposal = json.loads(match.group(0))
    except json.JSONDecodeError as e:
        print(f"invalid JSON from backend: {e}")
        return 1

    added_terms = 0
    for term in proposal.get("new_terms", []):
        if term and term not in glossary["terms"] and len(glossary["terms"]) < MAX_TERMS:
            glossary["terms"].append(term)
            added_terms += 1

    existing = {r["canonical"] for r in glossary["rules"]}
    added_rules = 0
    for rule in proposal.get("new_rules", []):
        canonical, pattern = rule.get("canonical"), rule.get("pattern")
        if not canonical or not pattern or canonical in existing:
            continue
        try:
            re.compile(pattern)
        except re.error:
            print(f"skipping bad pattern for {canonical}")
            continue
        glossary["rules"].append({"canonical": canonical, "pattern": pattern})
        existing.add(canonical)
        added_rules += 1

    if added_terms or added_rules:
        with open(GLOSSARY_PATH, "w", encoding="utf-8") as f:
            json.dump(glossary, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(f"added {added_terms} terms, {added_rules} rules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
