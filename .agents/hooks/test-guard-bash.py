#!/usr/bin/env python3
"""Table-driven check for guard-bash.py.

The allow cases matter more than the block cases: a blocking hook that fires on
a legitimate command is worse than no hook, because the next person turns it
off. Every allow case below is a real command shape from this repo's workflow.

Run: python3 .agents/hooks/test-guard-bash.py
"""

import json
import pathlib
import subprocess
import sys

GUARD = pathlib.Path(__file__).with_name("guard-bash.py")

CASES = [
    # Blocks — each one cost this repo real time.
    ("block", "local ios build", "make ios-build"),
    ("block", "local testflight after cd", "cd /x && make testflight"),
    ("block", "local install with variable", "make install DEVICE=2830"),
    ("block", "bump piped to head", "make bump 2>&1 | tee log | head -2"),
    ("block", "generate piped to tail", "make generate | tail -3"),
    (
        "block",
        "partial derived data delete",
        "rm -rf /U/x/AppDerivedData/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules",
    ),
    # Allows — false positives here are what kill a guard's credibility.
    ("allow", "quoted ssh payload", 'ssh -o BatchMode=yes studio "cd /x && make ios-build"'),
    ("allow", "timeout wrapped ssh", 'timeout 900 ssh -o BatchMode=yes studio "make test"'),
    ("allow", "bump redirected then read", "make bump > /tmp/log 2>&1; head -1 /tmp/log"),
    ("allow", "whole Build dir removal", "rm -rf /U/release-lane/AppDerivedData/Build"),
    ("allow", "host build on linux", "make host-build"),
    ("allow", "host test on linux", "make host-test"),
    ("allow", "plain git status", "git status --short"),
    ("allow", "grep naming a target", 'grep -rn "ios-test" Makefile'),
    ("allow", "echo naming a target", 'echo "run make testflight on studio"'),
    ("allow", "heredoc naming targets", "cat <<'EOF' > /tmp/s.sh\nmake ios-build\nmake testflight\nEOF"),
    ("allow", "empty command", ""),
]


def main() -> int:
    failures = 0
    for want, description, command in CASES:
        result = subprocess.run(
            [sys.executable, str(GUARD)],
            input=json.dumps({"tool_input": {"command": command}}),
            capture_output=True,
            text=True,
        )
        got = "block" if result.returncode == 2 else "allow"
        ok = got == want
        failures += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'}  {description:<30} want={want} got={got}")
        if not ok and result.stderr.strip():
            print("        ", result.stderr.strip()[:120])
    print(f"\n{len(CASES) - failures}/{len(CASES)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
