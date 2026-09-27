#!/usr/bin/env python3
"""Copy the X OAuth client id into the built Mac app's Info.plist.

Android bakes CLIENT_ID from .env. The Mac target has no Gradle step, so without
this the app sends the placeholder client id and X refuses the grant.
The script prints no secret values.
"""

from __future__ import annotations

import os
import plistlib
import sys
from pathlib import Path


def usable(raw: str | None) -> str | None:
    if raw is None:
        return None
    value = raw.strip().strip('"').strip("'")
    if not value or value.startswith("$(") or value.startswith("ROTATE") or value.startswith("MY_"):
        return None
    return value


def read_prop(path: Path, key: str) -> str | None:
    if not path.is_file():
        return None
    found = None
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        name, value = stripped.split("=", 1)
        if name.strip() == key:
            found = value
    return usable(found)


def resolve_client_id(root: Path, baked: str) -> str:
    local = read_prop(root / "local.properties", "X_CLIENT_ID")
    env = read_prop(root / ".env", "CLIENT_ID")
    return local or env or baked


def resolve_redirect(root: Path) -> str | None:
    return read_prop(root / "local.properties", "X_REDIRECT_URI") or read_prop(
        root / ".env", "X_REDIRECT_URI"
    )


def inject(plist_path: Path, root: Path, baked: str) -> None:
    with plist_path.open("rb") as handle:
        plist = plistlib.load(handle)
    client = resolve_client_id(root, baked)
    plist["CLIENT_ID"] = client
    redirect = resolve_redirect(root)
    if redirect:
        plist["X_REDIRECT_URI"] = redirect
    with plist_path.open("wb") as handle:
        plistlib.dump(plist, handle)


def main() -> int:
    srcroot = Path(os.environ.get("SRCROOT", Path(__file__).resolve().parents[1]))
    root = srcroot.parent if srcroot.name == "macos" else srcroot
    built = os.environ.get("TARGET_BUILD_DIR")
    info = os.environ.get("INFOPLIST_PATH")
    if not built or not info:
        print("inject_oauth_client: TARGET_BUILD_DIR or INFOPLIST_PATH is unset", file=sys.stderr)
        return 1
    plist_path = Path(built) / info
    if not plist_path.is_file():
        print(f"inject_oauth_client: Info.plist not found at {plist_path}", file=sys.stderr)
        return 1
    baked = "S2l6bVJubWFrTmh1emUxYW45dmM6MTpjaQ"
    inject(plist_path, root, baked)
    source = "default"
    if read_prop(root / "local.properties", "X_CLIENT_ID"):
        source = "local.properties"
    elif read_prop(root / ".env", "CLIENT_ID"):
        source = ".env"
    print(f"inject_oauth_client: wrote CLIENT_ID from {source} into {plist_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
