#!/usr/bin/env python3
# flat-launch: lists resumable agent sessions as JSON.
#   sessions.py [LIMIT]
# Claude: ~/.claude/projects/*/<id>.jsonl, title = last custom-title, else ai-title.
# pi: ~/.pi/agent/sessions/*/<ts>_<id>.jsonl, title = last session_info name.
# Either falls back to the first real user message. Newest first.
#
# Session files are append-only logs, so each one is read once: the cache keeps,
# per file, the byte offset read up to (always a line end) and what was found so
# far. A later run reads only the lines added since. A file smaller than its
# offset was rewritten, and is read again in full. The cache also holds the last
# list printed, which the launcher shows before this script finishes.
import glob, json, os, sys

home = os.path.expanduser("~")
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 120
cache_dir = f"{home}/.cache/flat-launch"  # main.js reads the list from here too
cache_path = f"{cache_dir}/sessions.json"
list_path = f"{cache_dir}/sessions-list.json"
VERSION = 1


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


def lines(path, st):
    """Yields (first, text) for complete lines past st["offset"], advancing it."""
    with open(path, "rb") as f:
        f.seek(st["offset"])
        for raw in f:
            if not raw.endswith(b"\n"):
                return  # still being written: read it next time
            first = st["offset"] == 0
            st["offset"] += len(raw)
            yield first, raw.decode("utf-8", "replace")


def claude(path, st):
    for _, line in lines(path, st):
        if '"custom-title"' in line or '"ai-title"' in line or (st.get("cwd") is None and '"cwd"' in line) \
                or (st.get("prompt") is None and '"type":"user"' in line):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = d.get("type")
            if t == "custom-title":
                st["custom"] = d.get("customTitle") or st.get("custom")
            elif t == "ai-title":
                st["ai"] = d.get("aiTitle") or st.get("ai")
            if st.get("cwd") is None and d.get("cwd"):
                st["cwd"] = d["cwd"]
            if st.get("prompt") is None and t == "user" and not d.get("isMeta"):
                s = text_of((d.get("message") or {}).get("content")).strip()
                if s and not s.startswith("<"):
                    st["prompt"] = first_line(s)


def claude_entry(path, st):
    title = st.get("custom") or st.get("ai") or st.get("prompt")
    if not st.get("cwd") or not title:
        return None
    sid = os.path.basename(path)[:-6]
    return {"agent": "claude", "id": sid, "folder": st["cwd"], "title": title,
            "titled": bool(st.get("custom") or st.get("ai")), "argv": ["claude", "--resume", sid]}


def pi(path, st):
    for first, line in lines(path, st):
        if first or '"session_info"' in line or (st.get("prompt") is None and '"role":"user"' in line):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") == "session":
                st["cwd"] = d.get("cwd")
            elif d.get("type") == "session_info":
                st["name"] = d.get("name") or st.get("name")
            elif st.get("prompt") is None and (d.get("message") or {}).get("role") == "user":
                s = text_of(d["message"].get("content")).strip()
                if s:
                    st["prompt"] = first_line(s)


def pi_entry(path, st):
    title = st.get("name") or st.get("prompt")
    if not st.get("cwd") or not title:
        return None
    return {"agent": "pi", "id": os.path.basename(path), "folder": st["cwd"], "title": title,
            "titled": bool(st.get("name")), "argv": ["pi", "--session", path]}


def load_cache():
    try:
        with open(cache_path) as f:
            c = json.load(f)
        return c["files"] if c.get("v") == VERSION else {}
    except (OSError, ValueError, KeyError, TypeError):
        return {}


def save(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


cache = load_cache()
files = [(p, claude, claude_entry) for p in glob.glob(f"{home}/.claude/projects/*/*.jsonl")]
files += [(p, pi, pi_entry) for p in glob.glob(f"{home}/.pi/agent/sessions/*/*.jsonl")]
stats = []
for p, read, entry in files:
    try:
        s = os.stat(p)
    except OSError:
        continue
    stats.append((s.st_mtime, s.st_size, p, read, entry))
stats.sort(reverse=True)

out, kept = [], {}
for mtime, size, p, read, entry in stats:
    st = cache.get(p)
    if len(out) >= limit:
        if st:
            kept[p] = st  # past the limit: keep what we know, read nothing
        continue
    if not st or size < st.get("offset", 0):
        st = {"offset": 0}
    if size > st["offset"]:
        try:
            read(p, st)
        except OSError:
            continue
    kept[p] = st
    s = entry(p, st)
    if s:
        s["mtime"] = int(mtime)
        out.append(s)

try:
    os.makedirs(cache_dir, exist_ok=True)
    save(cache_path, {"v": VERSION, "files": kept})
    save(list_path, out)
except OSError:
    pass
json.dump(out, sys.stdout)
