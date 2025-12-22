import json
import os
import sys
import urllib.parse
import urllib.request

BASE = "https://gitlab.freedesktop.org/api/v4"
PROJECT = "mesa/mesa"
REF = "main"
JOB_NAME = "a750-vk"

def die(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)

def api_get_json(path: str, token: str, params: dict | None = None):
    url = f"{BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)

    req = urllib.request.Request(url)
    req.add_header("PRIVATE-TOKEN", token)
    req.add_header("User-Agent", "tudev-guard")

    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8")
            data = json.loads(body) if body else None
            return data, r.headers
    except Exception as e:
        die(f"GitLab API failed: {url} ({e})")

def api_iter_list(path: str, token: str, params: dict | None = None):
    page = 1
    while True:
        p = dict(params or {})
        p.setdefault("per_page", "100")
        p["page"] = str(page)

        data, headers = api_get_json(path, token, p)
        if data is None:
            return
        if not isinstance(data, list):
            die(f"Unexpected response (expected list) for {path}")

        for item in data:
            yield item

        next_page = headers.get("X-Next-Page")
        if not next_page:
            break
        page = int(next_page)

def write_output(key: str, value: str) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")
    else:
        print(f"{key}={value}")

def job_name_ok(name: object) -> bool:
    return str(name or "").startswith(JOB_NAME)

def main() -> None:
    token = os.environ.get("GITLAB_TOKEN")
    if not token:
        die("GITLAB_TOKEN is required")

    max_commits = int(os.environ.get("MAX_COMMITS", "60"))
    if max_commits <= 0:
        die("MAX_COMMITS must be > 0")

    target_ref = os.environ.get("TARGET_REF", REF)
    project_path = os.environ.get("GITLAB_PROJECT_PATH")
    proj = project_path if project_path else urllib.parse.quote(PROJECT, safe="")

    commits, _ = api_get_json(
        f"/projects/{proj}/repository/commits",
        token,
        {"ref_name": target_ref, "per_page": str(max_commits)},
    )
    if not commits or not isinstance(commits, list):
        die(f"No commits found on {target_ref}")

    for c in commits:
        sha = (c or {}).get("id")
        if not sha:
            continue

        pipelines, _ = api_get_json(
            f"/projects/{proj}/pipelines",
            token,
            {
                "sha": sha,
                "status": "success",
                "order_by": "updated_at",
                "sort": "desc",
                "per_page": "20",
            },
        )
        if not pipelines or not isinstance(pipelines, list):
            continue

        for p in pipelines:
            pid = (p or {}).get("id")
            if not pid:
                continue

            jobs, _ = api_get_json(
                f"/projects/{proj}/pipelines/{pid}/jobs",
                token,
                {"per_page": "200"},
            )
            if not jobs or not isinstance(jobs, list):
                continue

            ok = any(job_name_ok(j.get("name")) and j.get("status") == "success" for j in jobs)
            if ok:
                write_output("FOUND", "true")
                write_output("MESA_BASELINE_SHA", sha)
                print(f"Chosen Mesa baseline: {sha} (pipeline {pid})", file=sys.stderr)
                return

    write_output("FOUND", "false")
    write_output("MESA_BASELINE_SHA", "")
    print(
        f"::notice::Skip build: No '{JOB_NAME}' success found in last {max_commits} commits on ref '{target_ref}'",
        file=sys.stderr,
    )
    return

if __name__ == "__main__":
    main()
