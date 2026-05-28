#!/usr/bin/env python3
"""aictrl CRM helper — direct Google Sheets API access (no interactive MCP).

Why this exists: the daily cron runs `claude -p` headless, where the Google
Workspace MCP can't complete its interactive OAuth handshake and stalls. This
helper talks to the Sheets REST API using the SAME saved Google login
(refresh token in the gws-mcp creds file), so a background job needs no human.

Subcommands:
  candidates [operator_user_id]
      Fetch scheduled linkedin_step_connect tasks from Apollo (H1/H2/H3) for the
      given operator, join against the CRM Log tab, and print up to 15
      connectable rows (col R empty, slug present, not already sent) as JSON.
  update <row> <R> <S> <T> <U> <V> <W> <X>
      Write the 7 LinkedIn-result columns to Log!R{row}:X{row} (RAW).

Env: APOLLO_API_KEY (from ~/.claude/secrets.env) for `candidates`.
"""
import json, os, sys, datetime, urllib.request, urllib.parse

CREDS = os.path.expanduser("~/.google_workspace_mcp/credentials/Info@boller.store.json")
SID = "1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ"
SEQS = ["69fde3942587c500119a8f10", "6a032c60fb3a7d0015fe647d", "6a04848c82740000159786ed"]
VAS_USER_ID = "69fc6082065486001538f103"


def access_token():
    d = json.load(open(CREDS))
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token", "refresh_token": d["refresh_token"],
        "client_id": d["client_id"], "client_secret": d["client_secret"]}).encode()
    return json.load(urllib.request.urlopen(urllib.request.Request(d["token_uri"], data=body)))["access_token"]


def sheet_get(tok, rng):
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{SID}/values/" + urllib.parse.quote(rng) + "?majorDimension=ROWS"
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"}))).get("values", [])


def sheet_put(tok, rng, values):
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{SID}/values/" + urllib.parse.quote(rng) + "?valueInputOption=RAW"
    data = json.dumps({"range": rng, "majorDimension": "ROWS", "values": values}).encode()
    req = urllib.request.Request(url, data=data, method="PUT",
                                 headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))


def apollo_tasks(operator):
    key = os.environ.get("APOLLO_API_KEY")
    if not key:  # fall back to the secrets file so headless callers need no `source`
        try:
            for line in open(os.path.expanduser("~/.claude/secrets.env")):
                if line.strip().startswith("APOLLO_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
        except OSError:
            pass
    if not key:
        sys.exit("APOLLO_API_KEY not found (env or ~/.claude/secrets.env)")
    out = []
    for page in range(1, 10):
        body = json.dumps({"per_page": 100, "page": page, "task_priority_status_cd": "scheduled",
                           "emailer_campaign_ids": SEQS, "open_factor_names": ["task_types"]}).encode()
        req = urllib.request.Request("https://api.apollo.io/api/v1/tasks/search", data=body,
                                     headers={"X-Api-Key": key, "Content-Type": "application/json", "Cache-Control": "no-cache"})
        resp = json.load(urllib.request.urlopen(req))
        for t in resp.get("tasks", []):
            if t.get("type") == "linkedin_step_connect" and t.get("status") == "scheduled" and t.get("user_id") == operator:
                out.append({"id": t["id"], "contact_id": t["contact_id"], "due": (t.get("due_at") or "")[:10]})
        if page >= resp.get("pagination", {}).get("total_pages", 1):
            break
    out.sort(key=lambda x: x["due"])  # earliest due first
    return out


def cmd_candidates(operator):
    """Connect candidates: grade-A unconnected leads FIRST (our hand-picked priority),
    then the Apollo task backlog. Unified on the Log tab."""
    tok = access_token()
    rows = sheet_get(tok, "Log!A2:S5000")
    crm = {}
    log_rows = []
    for i, r in enumerate(rows):
        def c(n):
            return (r[n] if len(r) > n else "").strip()
        rec = {"row": i + 2, "slug": c(7), "cid": c(8), "acct": c(9), "seq": c(10),
               "grade": c(14), "R": c(17), "S": c(18)}
        log_rows.append(rec)
        if rec["cid"]:
            crm[rec["cid"]] = rec
    tasks = apollo_tasks(operator)  # earliest-due first
    task_by_cid = {t["contact_id"]: t["id"] for t in tasks}
    cand, seen = [], set()
    # 1) priority — grade A, has slug, not yet connected
    for rec in log_rows:
        if rec["grade"] == "A" and rec["slug"] and not rec["R"] and not rec["S"].startswith("sent"):
            cand.append({"task_id": task_by_cid.get(rec["cid"], ""), "contact_id": rec["cid"],
                         "row": rec["row"], "slug": rec["slug"], "acct": rec["acct"],
                         "seq": rec["seq"] or "priority (grade A)", "due": ""})
            seen.add(rec["row"])
            if len(cand) >= 15:
                break
    # 2) backlog — Apollo task queue, oldest due first
    if len(cand) < 15:
        for t in tasks:
            e = crm.get(t["contact_id"])
            if not e or e["row"] in seen or e["R"] or not e["slug"] or e["S"].startswith("sent"):
                continue
            cand.append({"task_id": t["id"], "contact_id": t["contact_id"], "row": e["row"],
                         "slug": e["slug"], "acct": e["acct"], "seq": e["seq"], "due": t["due"]})
            seen.add(e["row"])
            if len(cand) >= 15:
                break
    print(json.dumps(cand))


def cmd_update(args):
    row = int(args[0])
    vals = args[1:8]
    vals += [""] * (7 - len(vals))
    sheet_put(access_token(), f"Log!R{row}:X{row}", [vals])
    print(f"updated row {row}")


def cmd_pending(limit):
    """List CRM rows with col W == 'pending' (invites awaiting acceptance)."""
    tok = access_token()
    rows = sheet_get(tok, "Log!A2:Z5000")
    out = []
    for i, r in enumerate(rows):
        W = (r[22] if len(r) > 22 else "").strip()
        slug = (r[7] if len(r) > 7 else "").strip()
        if W != "pending" or not slug:
            continue
        out.append({"row": i + 2, "slug": slug,
                    "name": (r[1] if len(r) > 1 else "").strip(),
                    "title": (r[2] if len(r) > 2 else "").strip(),
                    "company": (r[3] if len(r) > 3 else "").strip(),
                    "connect_date": (r[17] if len(r) > 17 else "").strip()})
        if len(out) >= limit:
            break
    print(json.dumps(out))


def cmd_track_update(args):
    """Write the tracker's columns: Log!W{row}:Z{row} = [W, X, Y, Z]."""
    row = int(args[0])
    vals = args[1:5]
    vals += [""] * (4 - len(vals))
    sheet_put(access_token(), f"Log!W{row}:Z{row}", [vals])
    print(f"tracked row {row}")


def cmd_email_update(args):
    """Advance a Log row's OUR-email columns: AA:AE = [status, step, last_sent, next_due, reply?]."""
    row = int(args[0])
    vals = args[1:6]
    vals += [""] * (5 - len(vals))
    sheet_put(access_token(), f"Log!AA{row}:AE{row}", [vals])
    print(f"email-updated row {row}")


def cmd_due_steps(limit):
    """Log rows whose next OUR-email step is due: Email Status (AA) queued/active,
    no Email Reply (AE), Email Next Due (AD) <= today. Grade A first. Rows whose
    Email Status starts with 'skip' (e.g. already in an Apollo email sequence) are
    excluded so we never double-email."""
    tok = access_token()
    today = datetime.date.today().isoformat()
    rows = sheet_get(tok, "Log!A2:AF5000")
    out = []
    for i, r in enumerate(rows):
        def c(n):
            return (r[n] if len(r) > n else "").strip()
        status, reply, nextdue = c(26), c(30), c(29)  # AA, AE, AD
        if status not in ("queued", "active") or reply:
            continue
        if c(14) != "A":  # our cron emails grade-A only (B+ handled by Apollo)
            continue
        if not nextdue or nextdue > today:
            continue
        name = c(1)
        out.append({"row": i + 2, "first": name.split()[0] if name else "", "name": name,
                    "company": c(3), "email": c(5), "grade": c(14),
                    "step_done": c(27) or "0", "why": c(31)})
    out.sort(key=lambda x: (x["grade"] or "Z", x["row"]))  # A before B before ungraded
    print(json.dumps(out[:limit]))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "candidates":
        cmd_candidates(sys.argv[2] if len(sys.argv) > 2 else VAS_USER_ID)
    elif cmd == "update":
        cmd_update(sys.argv[2:])
    elif cmd == "pending":
        cmd_pending(int(sys.argv[2]) if len(sys.argv) > 2 else 50)
    elif cmd == "track-update":
        cmd_track_update(sys.argv[2:])
    elif cmd == "due-steps":
        cmd_due_steps(int(sys.argv[2]) if len(sys.argv) > 2 else 5)
    elif cmd == "email-update":
        cmd_email_update(sys.argv[2:])
    else:
        sys.exit(f"unknown command: {cmd}")
