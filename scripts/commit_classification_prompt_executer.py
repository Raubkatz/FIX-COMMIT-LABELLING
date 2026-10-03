#!/usr/bin/env python3
"""
Standalone second half of the commit-bugfix-classification pipeline.

It reads a prompts JSON produced by CommitClassificationPromptMiner, runs every prompt
against the chosen model, and folds the results into the out CSV as a new
`*_<model>` column group. The CSV does not need to exist — it is created if missing.
Re-running the same model updates its columns in place rather than duplicating them.

Standard library only (no third-party dependencies).
"""
import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

csv.field_size_limit(10**9)  # commit messages can exceed the 128KB csv default

DEFAULT_BASE_URL = "http://localhost:11434"
DEFAULT_MODEL = "qwen3.5:9b"

# Smaller models (codegemma, llama3, ...) often ignore format:"json" and return
# fenced, prose-wrapped, or slightly malformed JSON (e.g. a missing comma between
# fields). We only need the bugfix verdict and optional reason, so fall back to
# regex extraction when strict JSON parsing of the model's answer fails.
_BUGFIX_RE = re.compile(r'[\'"]?bugfix[\'"]?\s*[:=]\s*[\'"]?(true|false)', re.IGNORECASE)
_REASON_RE = re.compile(r'[\'"]?reason[\'"]?\s*[:=]\s*[\'"]([^\'"]*)[\'"]', re.IGNORECASE)


def parse_classification(text):
    """
    Best-effort extraction of {"bugfix": bool, "reason": str?} from a model answer.
    Returns a dict or None if no bugfix verdict can be found.
    """
    if text is None:
        return None

    # 1. Strict JSON, including the substring between the first '{' and last '}'
    #    (handles code fences / leading or trailing prose around the object).
    candidates = [text]
    start, end = text.find("{"), text.rfind("}")
    if start != -1 and end > start:
        candidates.append(text[start:end + 1])
    for cand in candidates:
        try:
            obj = json.loads(cand)
            if isinstance(obj, dict) and "bugfix" in obj:
                return {"bugfix": bool(obj["bugfix"]), "reason": obj.get("reason")}
        except Exception:
            pass

    # 2. Regex fallback for malformed JSON (missing commas, single quotes, etc.).
    m = _BUGFIX_RE.search(text)
    if not m:
        return None
    reason_match = _REASON_RE.search(text)
    return {"bugfix": m.group(1).lower() == "true",
            "reason": reason_match.group(1) if reason_match else None}


# ---------------------------------------------------------------------------
# Ollama client (port of OllamaClient.kt, runBugfixPrompt + isAvailable)
# ---------------------------------------------------------------------------
DEFAULT_REQUEST_TIMEOUT = 120   # seconds per classification request (was 30)


class OllamaClient:
    def __init__(self, model, base_url=DEFAULT_BASE_URL, num_predict=None, num_ctx=None,
                 request_timeout=DEFAULT_REQUEST_TIMEOUT):
        self.model = model
        self.base_url = base_url
        # Optional override of the mined per-prompt num_predict. Some models (e.g.
        # codegemma) emit extra newline tokens and hit a tight cap before closing
        # the JSON object (done_reason="length"), so they need more headroom.
        self.num_predict = num_predict
        # Optional override of the mined per-prompt num_ctx. Long commit messages can
        # overflow the small mined context window (1024/4096), leaving no room to answer.
        self.num_ctx = num_ctx
        self.request_timeout = request_timeout

    def is_available(self):
        url = f"{self.base_url}/api/tags"
        print(f"[Ollama] availability check start | url={url}")
        try:
            req = urllib.request.Request(url, method="GET")
            start = time.monotonic()
            with urllib.request.urlopen(req, timeout=3) as resp:
                status = resp.status
            duration_ms = int((time.monotonic() - start) * 1000)
            print(f"[Ollama] availability check done | status={status} | durationMs={duration_ms}")
            return status == 200
        except Exception as e:
            print(f"[Ollama] availability check failed | type={type(e).__name__} | message={e}",
                  file=sys.stderr)
            return False

    def run_bugfix_prompt(self, prompt, options):
        """
        Executes an already-built bugfix prompt against the configured model and parses the
        {"bugfix": ..., "reason": ...} answer. Returns a BugfixResult dict or None on failure.
        """
        if self.num_predict is not None:
            options = {**options, "num_predict": self.num_predict}
        if self.num_ctx is not None:
            options = {**options, "num_ctx": self.num_ctx}
        request_body = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "think": False,
            "keep_alive": "30m",
            "options": options,
        }
        data = json.dumps(request_body).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=self.request_timeout) as resp:
                status = resp.status
                body = resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8", errors="replace") if e.fp else ""
            error_preview = error_body.replace("\n", "\\n")[:500]
            print(f"[Ollama] runBugfixPrompt non-200 | status={e.code} | body={error_preview}",
                  file=sys.stderr)
            return None
        except Exception as e:
            print(f"[Ollama] runBugfixPrompt failed | type={type(e).__name__} | message={e}",
                  file=sys.stderr)
            return None

        if status != 200:
            error_preview = body.replace("\n", "\\n")[:500]
            print(f"[Ollama] runBugfixPrompt non-200 | status={status} | body={error_preview}",
                  file=sys.stderr)
            return None

        try:
            try:
                ollama_response = json.loads(body)
            except Exception:
                # Fall back to the last non-empty line (defensive against streamed/NDJSON bodies).
                last_non_empty = next(
                    line.strip() for line in reversed(body.splitlines()) if line.strip()
                )
                ollama_response = json.loads(last_non_empty)

            result = parse_classification(ollama_response.get("response"))
            if result is None:
                resp = ollama_response.get("response") or ""
                preview = resp.replace("\n", "\\n")[:300]
                done_reason = ollama_response.get("done_reason")
                eval_count = ollama_response.get("eval_count")
                prompt_tokens = ollama_response.get("prompt_eval_count")
                cap = options.get("num_predict")
                num_ctx = options.get("num_ctx")
                # The prompt (after Ollama truncates it to num_ctx) fills the whole context,
                # so there is no room left to generate an answer.
                context_full = (num_ctx is not None and prompt_tokens is not None
                                and prompt_tokens + (eval_count or 0) >= num_ctx)
                # Did the model generate any real content, or just braces/whitespace?
                has_content = any(c.isalnum() for c in resp)
                if not resp.strip() and not context_full:
                    diagnosis = "model returned an empty response"
                elif done_reason == "length" and context_full:
                    diagnosis = (f"prompt is {prompt_tokens} tokens but num_ctx is {num_ctx} -- "
                                 f"the context window is full, so the model could only emit "
                                 f"{eval_count} token(s) before stopping; raise num_ctx with "
                                 f"--num-ctx (or shorten the prompt, e.g. strip diffs / long messages)")
                elif done_reason == "length" and not has_content:
                    diagnosis = (f"model spent its whole token budget ({eval_count}/{cap}) on "
                                 f"whitespace without emitting any JSON content -- it is not "
                                 f"following the format for this prompt (raising --num-predict "
                                 f"will not help)")
                elif done_reason == "length":
                    diagnosis = (f"output cut off at the num_predict cap ({eval_count}/{cap} "
                                 f"tokens, JSON never closed) -> raise --num-predict")
                else:
                    diagnosis = "no bugfix verdict (true/false) found in the model output"
                print(f"[Ollama] runBugfixPrompt: {diagnosis} | done_reason={done_reason} "
                      f"prompt_eval_count={prompt_tokens} eval_count={eval_count} "
                      f'num_ctx={num_ctx} num_predict={cap} | response="{preview}"',
                      file=sys.stderr)
            return result
        except Exception as e:
            print(f"[Ollama] runBugfixPrompt failed | type={type(e).__name__} | message={e}",
                  file=sys.stderr)
            return None


# ---------------------------------------------------------------------------
# Progress tracker (port of ProgressTracker in LlmClassificationCommand.kt)
# ---------------------------------------------------------------------------
def _format_duration(duration_ms):
    total_seconds = duration_ms // 1000
    return "%02d:%02d" % (total_seconds // 60, total_seconds % 60)


class ProgressTracker:
    def __init__(self, total, label="Item"):
        self.total = total
        self.label = label
        self.processed = 0
        # Clock starts on the first tick (when the first real prompt begins), so
        # model warmup / setup time never leaks into the elapsed time and ETA.
        self.start_time = None

    def tick(self):
        self.processed += 1
        if self.start_time is None:
            self.start_time = time.monotonic()
        if self.processed > 1:
            elapsed_ms = int((time.monotonic() - self.start_time) * 1000)
            estimated_total_ms = int((elapsed_ms / (self.processed - 1)) * self.total)
            print(f"{self.label} {self.processed} / {self.total} | "
                  f"{_format_duration(elapsed_ms)}/{_format_duration(estimated_total_ms)}")


# ---------------------------------------------------------------------------
# CSV folding (port of modelColumns/modelFields/createCsv/updateExistingCsv)
# ---------------------------------------------------------------------------
def model_columns(model, with_reason):
    cols = [f"isBugfix_{model}"]
    if with_reason:
        cols.append(f"reason_{model}")
    return cols


def model_fields(result, with_reason):
    fields = [str(bool(result["bugfix"])).lower() if result else "false"]
    if with_reason:
        fields.append((result.get("reason") if result else None) or "")
    return fields


def _atomic_write_csv(csv_path, headers, rows):
    parent = os.path.dirname(csv_path) or "."
    name_without_ext = os.path.splitext(os.path.basename(csv_path))[0]
    tmp_path = os.path.join(parent, f"{name_without_ext}.csv.tmp")
    # newline="" + the default dialect mirror Apache Commons CSVFormat.DEFAULT (CRLF, comma).
    with open(tmp_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(rows)
    os.replace(tmp_path, csv_path)


def update_existing_csv(csv_path, model, results, with_reason):
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        existing_headers = list(reader.fieldnames or [])
        records = [(row, row.get("hash")) for row in reader]

    new_columns = model_columns(model, with_reason)
    # Re-running the same model updates its columns in place rather than duplicating them.
    headers = existing_headers + [c for c in new_columns if c not in existing_headers]

    rows = []
    for row, h in records:
        model_values = dict(zip(new_columns, model_fields(results.get(h), with_reason)))
        rows.append([model_values.get(col, row.get(col, "") or "") for col in headers])

    _atomic_write_csv(csv_path, headers, rows)


def create_csv(csv_path, model, prompts_data, results):
    headers = ["hash"] + model_columns(model, prompts_data["withReason"])
    parent = os.path.dirname(csv_path)
    if parent:
        os.makedirs(parent, exist_ok=True)

    rows = []
    for p in prompts_data["prompts"]:
        rows.append([p["hash"]] + model_fields(results.get(p["hash"]), prompts_data["withReason"]))

    _atomic_write_csv(csv_path, headers, rows)


# ---------------------------------------------------------------------------
# Entry point (port of CommitClassificationPromptExecuter.run)
# ---------------------------------------------------------------------------
def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Execute mined commit-classification prompts on a model and update the out CSV",
    )
    parser.add_argument("--prompts", "-p", required=True,
                        help="Prompts JSON produced by CommitClassificationPromptMiner")
    parser.add_argument("--csv", "-c", required=True,
                        help="Out CSV to update (created if it does not exist)")
    parser.add_argument("--model-version", "-m", dest="model", default=DEFAULT_MODEL)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL,
                        help=f"Ollama base URL (default: {DEFAULT_BASE_URL})")
    parser.add_argument("--num-predict", type=int, default=None,
                        help="Override the mined num_predict token cap (raise it for models "
                             "like codegemma that get truncated mid-JSON; e.g. 64)")
    parser.add_argument("--num-ctx", type=int, default=None,
                        help="Override the mined num_ctx context window (raise it when long "
                             "commit messages overflow it and leave no room to answer; e.g. 8192)")
    parser.add_argument("--request-timeout", type=int, default=DEFAULT_REQUEST_TIMEOUT,
                        help=f"Per-prompt request timeout in seconds (default: {DEFAULT_REQUEST_TIMEOUT}). "
                             f"Preload big models with warmup_model.py first to avoid cold-load timeouts.")
    args = parser.parse_args(argv)

    if not os.path.isfile(args.prompts):
        sys.exit(f"ERROR: prompts file does not exist: {args.prompts}")

    with open(args.prompts, "r", encoding="utf-8") as f:
        prompts_data = json.load(f)

    client = OllamaClient(args.model, base_url=args.base_url, num_predict=args.num_predict,
                          num_ctx=args.num_ctx, request_timeout=args.request_timeout)
    if not client.is_available():
        print("ERROR: Ollama is not reachable.", file=sys.stderr)
        return 1

    prompts = prompts_data["prompts"]
    tracker = ProgressTracker(len(prompts), "Prompts")
    results = {}
    for p in prompts:
        tracker.tick()
        results[p["hash"]] = client.run_bugfix_prompt(p["prompt"], p["options"])

    if os.path.exists(args.csv):
        update_existing_csv(args.csv, args.model, results, prompts_data["withReason"])
    else:
        create_csv(args.csv, args.model, prompts_data, results)

    print(f"Done. Written to {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
