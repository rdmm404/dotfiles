#!/usr/bin/env python3
# flat-launch: lists resumable agent sessions as JSON.
#   sessions.py [LIMIT]
# Claude: ~/.claude/projects/*/<id>.jsonl, title = last custom-title, else ai-title.
# pi: ~/.pi/agent/sessions/*/<ts>_<id>.jsonl, title = last session_info name.
# Either falls back to the first real user message. Newest first.
import glob, json, os, sys

home = os.path.expanduser("~")
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 120


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for c in content:
            if isinstance(c, dict) and c.get("type") == "text":
                return c.get("text", "")
    return ""


def first_line(s):
    s = " ".join(s.split())
    return s[:120]


def claude(path):
    cwd = custom = ai = prompt = None
    with open(path, errors="replace") as f:
        for line in f:
            if '"custom-title"' in line or '"ai-title"' in line or (cwd is None and '"cwd"' in line) or (prompt is None and '"type":"user"' in line):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                t = d.get("type")
                if t == "custom-title":
                    custom = d.get("customTitle") or custom
                elif t == "ai-title":
                    ai = d.get("aiTitle") or ai
                if cwd is None and d.get("cwd"):
                    cwd = d["cwd"]
                if prompt is None and t == "user" and not d.get("isMeta"):
                    s = text_of((d.get("message") or {}).get("content")).strip()
                    if s and not s.startswith("<"):
                        prompt = first_line(s)
    if not cwd or not (custom or ai or prompt):
        return None
    sid = os.path.basename(path)[:-6]
    return {"agent": "claude", "id": sid, "folder": cwd, "title": custom or ai or prompt,
            "titled": bool(custom or ai), "argv": ["claude", "--resume", sid]}


def pi(path):
    cwd = name = prompt = None
    with open(path, errors="replace") as f:
        for i, line in enumerate(f):
            if i == 0 or '"session_info"' in line or (prompt is None and '"role":"user"' in line):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") == "session":
                    cwd = d.get("cwd")
                elif d.get("type") == "session_info":
                    name = d.get("name") or name
                elif prompt is None and (d.get("message") or {}).get("role") == "user":
                    s = text_of(d["message"].get("content")).strip()
                    if s:
                        prompt = first_line(s)
    if not cwd or not (name or prompt):
        return None
    return {"agent": "pi", "id": os.path.basename(path), "folder": cwd, "title": name or prompt,
            "titled": bool(name), "argv": ["pi", "--session", path]}


files = [(p, claude) for p in glob.glob(f"{home}/.claude/projects/*/*.jsonl")]
files += [(p, pi) for p in glob.glob(f"{home}/.pi/agent/sessions/*/*.jsonl")]
files = [(os.path.getmtime(p), p, fn) for p, fn in files]
files.sort(reverse=True)
out = []
for mtime, p, fn in files:
    if len(out) >= limit:
        break
    try:
        s = fn(p)
    except OSError:
        continue
    if s:
        s["mtime"] = int(mtime)
        out.append(s)
json.dump(out, sys.stdout)
