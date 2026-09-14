#!/usr/bin/env python3
"""Exercise the installer and real shell startup; run via test-install-docker.sh."""

import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = re.search(r'^host_version="([^"]+)"', (ROOT / "install.sh").read_text(), re.M)[1]
BASE_PATH = "/usr/local/bin:/usr/bin:/bin"


def run(args, env):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise AssertionError(f"{args}:\n{result.stdout}\n{result.stderr}")
    return result.stdout


with tempfile.TemporaryDirectory(prefix="herden-path-") as temporary:
    fixture = Path(temporary)
    release = fixture / "release"
    release.mkdir()
    asset = release / "herden-linux-x86_64"
    # A small release fixture exercises download, checksum and install without
    # needing to build the runtime. Pairing confirms dispatch of a plain command.
    asset.write_text(
        '#!/bin/sh\ncase "$1" in\n'
        f'--version) printf "%s\\n" "herden {VERSION}" ;;\n'
        'pair) printf "%s\\n" "pair reached" ;;\n'
        '*) exit 2 ;;\nesac\n'
    )
    (release / f"{asset.name}.sha256").write_text(hashlib.sha256(asset.read_bytes()).hexdigest())
    for name in ("LICENSE", "NOTICE"):
        (release / name).write_text(f"{name} fixture\n")

    cases = [
        ("bash-clean", "/bin/bash", {}, [".profile", ".bashrc"], None),
        ("bash-profile", "/bin/bash", {".bash_profile": "# keep me\n", ".profile": "# unused\n"}, [".bash_profile", ".bashrc"], None),
        ("bash-login", "/bin/bash", {".bash_login": "# keep me\n"}, [".bash_login", ".bashrc"], None),
        ("bash-existing", "/bin/bash", {name: 'export PATH="$HOME/.local/bin:$PATH"\n' for name in (".profile", ".bashrc")}, [".profile", ".bashrc"], None),
        ("bash-comment", "/bin/bash", {".bashrc": '# export PATH="$HOME/.local/bin:$PATH"\n'}, [".profile", ".bashrc"], None),
        ("bash-near-match", "/bin/bash", {".bashrc": 'export PATH="$HOME/.local/bin-extra:$PATH"\n'}, [".profile", ".bashrc"], None),
        ("bash-no-newline", "/bin/bash", {".bashrc": '# keep this comment'}, [".profile", ".bashrc"], None),
        ("bash-conditional", "/bin/bash", {".profile": 'if [ -d "$HOME/.local/bin" ]; then\n    PATH="$HOME/.local/bin:$PATH"\nfi\n'}, [".profile", ".bashrc"], None),
        ("bash-early-return", "/bin/bash", {".bashrc": 'case $- in *i*) ;; *) return ;; esac\n'}, [".profile", ".bashrc"], None),
        ("zsh-clean", "/bin/zsh", {}, [".zprofile", ".zshrc"], None),
        ("zsh-existing", "/bin/zsh", {name: 'export PATH="${HOME}/.local/bin:$PATH"\n' for name in (".zprofile", ".zshrc")}, [".zprofile", ".zshrc"], None),
        ("zsh-zdotdir", "/bin/zsh", {}, ["config/zsh/.zprofile", "config/zsh/.zshrc"], None),
        ("posix", "/bin/dash", {}, [".profile"], None),
        ("no-shell", "", {}, [".profile"], None),
        ("already-in-path", "/bin/bash", {}, [".profile", ".bashrc"], None),
        ("custom-path", "/bin/bash", {}, [".profile", ".bashrc"], "tools/bin"),
        ("quoted-path", "/bin/bash", {}, [".profile", ".bashrc"], "tools ' $dollar `touch PWNED` $(touch PWNED) [x] \\tools/bin"),
        ("zsh-quoted-path", "/bin/zsh", {}, [".zprofile", ".zshrc"], "tools ' $dollar `touch PWNED` $(touch PWNED) [x] \\tools/bin"),
    ]

    for name, shell, initial, profiles, custom in cases:
        home = fixture / name
        home.mkdir()
        install_dir = home / (custom or ".local/bin")
        env = {k: v for k, v in os.environ.items() if not k.startswith(("HERDEN_", "HERDR_")) and k not in ("ZDOTDIR", "BASH_ENV", "ENV")}
        env.update(HOME=str(home), SHELL=shell, PATH=BASE_PATH, HERDEN_DOWNLOAD_ROOT=release.as_uri())
        if custom:
            env["HERDEN_INSTALL_DIR"] = str(install_dir)
        if name == "zsh-zdotdir":
            env["ZDOTDIR"] = str(home / "config/zsh")
        if name == "already-in-path":
            env["PATH"] = f"{install_dir}:{BASE_PATH}"
        for relative, content in initial.items():
            (home / relative).write_text(content)

        output = run(["/bin/sh", str(ROOT / "install.sh")], env)
        assert "herden pair" in output, output
        assert "To use Herden in this Terminal now" in output or name == "already-in-path", output
        before = {relative: (home / relative).read_bytes() for relative in profiles}
        run(["/bin/sh", str(ROOT / "install.sh")], env)
        assert before == {relative: (home / relative).read_bytes() for relative in profiles}, name
        for relative, content in initial.items():
            actual = (home / relative).read_text()
            assert actual.startswith(content), (name, relative)
            if name in ("bash-existing", "zsh-existing", "bash-conditional") or relative == ".profile" and name == "bash-profile":
                assert actual == content, (name, relative, actual)

        # Probe from a baseline without the install directory, even if it was
        # present at install time. Both future login and non-login terminals work.
        probe_env = dict(env, PATH=BASE_PATH)
        check = 'herden --version; herden pair; printf "PATH_RESULT=%s\\n" "$PATH"'
        if shell in ("/bin/bash", "/bin/zsh"):
            probes = [[shell, "-ic", check], [shell, "-lic", check]]
        else:
            probes = [[shell or "/bin/sh", "-c", '. "$HOME/.profile"; ' + check]]
        for probe in probes:
            output = run(probe, probe_env)
            assert f"herden {VERSION}\npair reached\n" in output, (name, output)
            path = output.split("PATH_RESULT=", 1)[1].splitlines()[0].split(":")
            # Both pre-existing zsh files deliberately contain an unconditional
            # export. Preserve them verbatim, including their own duplication.
            expected_count = 2 if name == "zsh-existing" and "-lic" in probe else 1
            assert path.count(str(install_dir)) == expected_count, (name, path)

        # Reproduce the documented copy/paste block, followed immediately by
        # the user's next command in the SAME shell, without sourcing profiles.
        command = (
            f"curl -fsSL {shlex.quote((ROOT / 'install.sh').as_uri())} | sh\n"
            f"export PATH={shlex.quote(str(install_dir))}:\"$PATH\"\n"
            "herden pair"
        )
        output = run([shell or "/bin/sh", "-c", command], probe_env)
        assert output.endswith("pair reached\n"), (name, output)
        assert not (ROOT / "PWNED").exists()
        print(f"PASS {name}: startup, repeat install, immediate pairing")

    # A profile we cannot update must produce an actionable failure, never a
    # success message falsely claiming the command is ready in future shells.
    home = fixture / "read-only-profile"
    home.mkdir()
    profile = home / ".profile"
    profile.write_text("# read-only profile\n")
    profile.chmod(0o444)
    env.update(HOME=str(home), SHELL="/bin/sh", HERDEN_INSTALL_DIR=str(home / ".local/bin"))
    result = subprocess.run(["/bin/sh", str(ROOT / "install.sh")], env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode != 0, result.stdout
    assert "could not add Herden to PATH" in result.stderr, result.stderr
    assert "is ready" not in result.stdout, result.stdout
    print("PASS read-only profile: actionable failure")

print(f"PATH behavior passed ({len(cases) + 1} scenarios)")
