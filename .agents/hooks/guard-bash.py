#!/usr/bin/env python3
"""Blocks the three Bash mistakes that have actually cost this repo a rebuild.

Every rule here is a hard stop, so each one has to be unambiguous: a blocking
hook that cries wolf gets switched off, and then it guards nothing. Advisory
notices belong in after-edit.sh instead.

Quoted spans and heredoc bodies are stripped before matching. That is what
keeps a remote payload (`ssh studio "make ios-build"`), a grep for a target
name, and a file written with `cat <<EOF` from reading as a local invocation —
the single most likely false positive, and one this repo's workflow hits
constantly because so much is written through heredocs.

Exit 0 allows with no opinion; exit 2 blocks and stderr becomes the reason.
Claude Code and Codex share that contract and both pass the shell command
as `tool_input.command`, so this one script serves both; only the wiring
differs (.claude/settings.json and .codex/hooks.json). pi has no hook
system at all and is deliberately uncovered.
"""

import json
import re
import subprocess
import sys


def strip_heredocs(command: str) -> str:
    """Drop heredoc bodies, keeping the line that opens them.

    A heredoc body is file content, not a command list. This repo writes
    scripts and fixtures through `cat <<'EOF'` constantly, and those bodies
    routinely name make targets.
    """
    lines = command.split("\n")
    out = []
    index = 0
    while index < len(lines):
        line = lines[index]
        out.append(line)
        index += 1
        for match in re.finditer(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line):
            terminator = match.group(2)
            while index < len(lines) and lines[index].strip() != terminator:
                index += 1
            if index < len(lines):
                index += 1  # consume the terminator itself
            break
    return "\n".join(out)


def strip_quoted(command: str) -> str:
    """Blank out single- and double-quoted spans, keeping the text length.

    Anything inside quotes is data or a payload for another host, never a
    command this machine is about to run.
    """
    out = []
    quote = None
    for char in command:
        if quote:
            out.append(" ")
            if char == quote:
                quote = None
            continue
        if char in "'\"":
            quote = char
            out.append(" ")
            continue
        out.append(char)
    return "".join(out)


def deny(reason: str) -> None:
    print(reason, file=sys.stderr)
    sys.exit(2)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command.strip():
        sys.exit(0)

    bare = strip_quoted(strip_heredocs(command))

    # An unquoted ssh invocation runs elsewhere; its arguments are not ours to
    # judge. Quoted payloads are already blanked out above.
    if re.search(r"(^|[;&|]\s*)(timeout\s+\S+\s+)?ssh\b", bare):
        sys.exit(0)

    # 1. iOS work never runs from a Linux checkout (CLAUDE.md > Conventions).
    ios_targets = (
        "ios-build|ios-build-sim|ios-test|ios-test-one|ios-test-all|ios-test-ssh"
        "|archive|upload|testflight|install|install-built|sim|publish"
    )
    if subprocess.run(
        ["uname", "-s"], capture_output=True, text=True
    ).stdout.strip() == "Linux" and re.search(
        rf"(^|[;&|]\s*)make\s+(?:[A-Z_]+=\S+\s+)*({ios_targets})\b", bare
    ):
        deny(
            "Refused: iOS builds, tests, installs, archives and TestFlight "
            "uploads run on macOS only, never from this Linux checkout "
            "(CLAUDE.md > Conventions). Run it on Studio over ssh instead."
        )

    # 2. Never pipe a generator into a pager. `make bump ... | head -2`
    #    SIGPIPE-killed xcodegen mid-write on 2026-09-12, leaving a
    #    project.pbxproj one build behind project.yml that then shipped.
    if re.search(r"(^|[;&|]\s*)(make\s+(bump|generate)\b|xcodegen\b)", bare) and re.search(
        r"\|\s*(head|tail)\b", bare
    ):
        deny(
            "Refused: piping 'make bump', 'make generate' or xcodegen into "
            "head/tail closes the pipe early and SIGPIPE-kills generation "
            "partway through, leaving a truncated Herden.xcodeproj. Redirect "
            "to a file, then read the file."
        )

    # 3. Never delete part of a DerivedData module graph. Removing only
    #    SwiftExplicitPrecompiledModules on 2026-09-12 left dangling module
    #    references and broke the next two runs worse than the stale cache.
    if re.search(r"(^|[;&|]\s*)rm\b[^;&|]*-\w*r", bare) and "Intermediates.noindex" in bare:
        deny(
            "Refused: deleting inside Intermediates.noindex leaves dangling "
            "precompiled-module references. Remove the whole <lane>/Build "
            "directory instead — that is the scoped invalidation the release "
            "runbook calls for."
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
