# Sync lessons

## 2026-09-08 — first ancestry-preserving sync

- Initial pristine baseline: `702aa1e45527509bec73dad9b8d443f449c0379b`
  (Herdr 0.8.2).
- First synchronized head: `68c7b78ec237034cbb0e21c8666842ed7991641d`
  (Herdr 0.9.0 plus four mainline commits).
- A one-time `ours` merge attached the exact baseline without changing the
  tree. `git merge -s subtree` then correctly mapped upstream root paths into
  `runtime/` and retained the exact upstream head as the merge's second parent.
- The first update had six conflict paths: `Cargo.toml`, `Cargo.lock`, the
  deliberately short runtime README, `tests/machine_setup.rs`, and two files in
  the marketplace worker that upstream removed. Package identity stayed
  `herden` at upstream's new version; new upstream test behavior was combined
  with Herden fixture names; the obsolete worker deletion was accepted.
- Ordinary tag fetching polluted Herden's tag namespace with 83 Herdr tags.
  They were removed locally and the remote was rebuilt as mainline-only with
  `--no-tags`. Do not repeat this.
- Upstream 0.9.0 remains protocol 22 but expands the schema. Regenerating the
  committed schema changed Swift wire types, so Studio validation is required.
  In particular, upstream replaced the shared `WorkspaceTarget` definition
  used by `workspace.close` with `WorkspaceCloseParams`; the iOS transport's
  cleanup request and `GeneratedWireTypesTests` had to adopt the new generated
  type. Studio then passed all 1,527 app tests and the separate HerdenSSH
  package suite.
- The first build filled the VM's tmpfs because the worktree and Rust/Zig
  caches were all under `/tmp`. Put build caches under the home filesystem.
- Parallel unit runs separately failed
  `plugin_link_creates_stable_config_and_state_dirs` and
  `finite_clipboard_commands_report_exit_status`; each exact test passed on an
  immediate rerun. These are suspected upstream filesystem/process races. Use
  a full single-threaded `cargo test --locked -- --test-threads=1` as the
  deterministic acceptance gate when parallel failures move between tests.
- `runtime/distribution/*.json` contains upstream history and assets for schema
  tests. Runtime network endpoints are separately pinned to
  `https://herden.3loc.ltd` in `src/update.rs` and `src/remote/attach.rs`; audit
  those constants after every sync.
- The old import had mechanically rebranded 104 files under `runtime/docs/`,
  including frozen version documentation. That subtree is not Herden's public
  site and is now kept byte-for-byte identical to upstream. Preserve it as an
  upstream-owned subtree in future merges instead of recreating that noisy
  delta.
- The Linux integration-test watchdog used to recognize test servers only
  when their executable lived below `runtime/target/debug`. An external
  `CARGO_TARGET_DIR` therefore made live-handoff tests falsely report no
  replacement PID. It now compares `/proc/<pid>/exe` with Cargo's actual
  `CARGO_BIN_EXE_herden`; keep external build caches outside the worktree.
