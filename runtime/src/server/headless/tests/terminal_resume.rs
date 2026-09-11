use super::*;
use crate::terminal::TerminalId;
use crate::terminal_theme::{
    DefaultColorKind, HostAppearance, RgbColor, TerminalQueryContext, TerminalTheme,
};

struct PendingFixture {
    server: HeadlessServer,
    terminals: Vec<TerminalId>,
}

impl PendingFixture {
    fn new(count: usize, command: &str) -> Self {
        let mut server = test_headless_server();
        server.app.state.default_shell = "/bin/sh".into();
        server.app.state.shell_mode = crate::config::ShellModeConfig::NonLogin;
        let mut workspace = crate::workspace::Workspace::test_new("resume-colours");
        for _ in 1..count {
            workspace.test_add_tab(Some("pending"));
        }
        let terminals: Vec<_> = workspace
            .tabs
            .iter()
            .map(|tab| workspace.terminal_id(tab.root_pane).unwrap().clone())
            .collect();
        server.app.state.workspaces = vec![workspace];
        server.app.state.active = Some(0);
        server.app.state.mode = crate::app::Mode::Terminal;
        server.app.state.ensure_test_terminals();
        server.app.state.view.terminal_area = Rect::new(0, 0, 140, 45);
        for id in &terminals {
            let terminal = server.app.state.terminals.get_mut(id).unwrap();
            terminal.cwd = std::env::temp_dir();
            terminal.pending_agent_resume_plan = Some(crate::agent_resume::AgentResumePlan {
                agent: "codex".into(),
                argv: vec!["/bin/sh".into(), "-c".into(), command.into()],
                dedupe_key: format!("resume-colours:{id}"),
            });
        }
        assert!(terminals
            .iter()
            .all(|id| server.app.terminal_runtimes.get(id).is_none()));
        Self { server, terminals }
    }

    fn attach(&mut self, client_id: u64, index: usize, takeover: bool) -> ClientReceivers {
        let (writer, control, render) = test_client_writer();
        self.server
            .handle_server_event(ServerEvent::ClientConnected {
                client_id,
                cols: 90,
                rows: 28,
                cell_width_px: 0,
                cell_height_px: 0,
                pixel_mouse: false,
                writer,
            });
        assert!(self
            .server
            .handle_server_event(ServerEvent::ClientControlTerminal {
                client_id,
                target: self.terminals[index].to_string(),
                takeover,
            }));
        ClientReceivers { control, render }
    }

    fn running(&self, index: usize) -> bool {
        self.server
            .app
            .terminal_runtimes
            .get(&self.terminals[index])
            .is_some()
    }
}

impl Drop for PendingFixture {
    fn drop(&mut self) {
        shutdown_test_runtimes(&mut self.server);
    }
}

struct ClientReceivers {
    control: std::sync::mpsc::Receiver<Vec<u8>>,
    render: std::sync::mpsc::Receiver<Vec<u8>>,
}

impl ClientReceivers {
    fn assert_no_shutdown(&self) {
        for bytes in self.control.try_iter() {
            assert!(!matches!(
                read_server_message(bytes),
                ServerMessage::ServerShutdown { .. }
            ));
        }
        for _ in self.render.try_iter() {}
    }
}

fn context(background: u8) -> TerminalQueryContext {
    TerminalQueryContext {
        theme: TerminalTheme {
            foreground: Some(RgbColor {
                r: 30,
                g: 30,
                b: 30,
            }),
            background: Some(RgbColor {
                r: background,
                g: background,
                b: background,
            }),
            ..Default::default()
        },
        appearance: Some(HostAppearance::Light),
    }
}

fn default_report(server: &mut HeadlessServer, client_id: u64, background: bool, value: u8) {
    server.handle_server_event(ServerEvent::ClientShellHostTheme {
        client_id,
        update: protocol::ClientHostThemeUpdate::DefaultColor {
            kind: if background {
                protocol::ClientHostDefaultColorKind::Background
            } else {
                protocol::ClientHostDefaultColorKind::Foreground
            },
            color: protocol::ClientHostColor {
                r: value,
                g: value,
                b: value,
            },
        },
    });
}

fn finish_report(server: &mut HeadlessServer, client_id: u64) {
    server.handle_server_event(ServerEvent::ClientShellHostTheme {
        client_id,
        update: protocol::ClientHostThemeUpdate::Appearance(protocol::ClientHostAppearance::Light),
    });
}

fn queried_background(server: &HeadlessServer, id: &TerminalId) -> RgbColor {
    let replies = server
        .app
        .terminal_runtimes
        .get(id)
        .unwrap()
        .test_terminal_query(b"\x1b]11;?\x07");
    let (kind, colour) = crate::terminal_theme::parse_default_color_response(
        std::str::from_utf8(&replies[0]).unwrap(),
    )
    .unwrap();
    assert_eq!(kind, DefaultColorKind::Background);
    colour
}

#[tokio::test]
async fn direct_pending_resume_child_reads_owner_colour_at_startup() {
    let observed = context(240);
    let probe = crate::terminal::TerminalRuntime::test_with_screen_bytes(90, 28, b"");
    probe.apply_desktop_terminal_appearance(observed.theme, observed.appearance);
    let replies = probe.test_terminal_query(b"\x1b]11;?\x07");
    assert_eq!(replies.len(), 1);
    let expected_hex: String = replies[0]
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    // The expected answer is absent from the command, so shell echo cannot
    // satisfy the assertion. A wrong or absent answer fails the bounded wait.
    let command = format!(
        "stty raw -echo; printf '\\033]11;?\\007'; reply=$(dd bs=1 count={} 2>/dev/null | od -An -tx1 | tr -d '[:space:]'); printf '\\r\\nSTARTUP_COLOUR:%s\\r\\n' \"$reply\"; sleep 5",
        replies[0].len()
    );
    let mut fixture = PendingFixture::new(1, &command);
    fixture.server.app.state.host_terminal_theme = context(87).theme;
    fixture.server.app.state.host_terminal_appearance = Some(HostAppearance::Dark);
    let _receivers = fixture.attach(7, 0, false);
    default_report(&mut fixture.server, 7, false, 30);
    default_report(&mut fixture.server, 7, true, 240);
    assert!(!fixture.running(0));
    finish_report(&mut fixture.server, 7);
    assert!(fixture.running(0));

    let marker = format!("STARTUP_COLOUR:{expected_hex}");
    let text = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let text = fixture
                .server
                .app
                .terminal_runtimes
                .get(&fixture.terminals[0])
                .unwrap()
                .snapshot_history()
                .unwrap_or_default();
            if text.contains(&marker) {
                break text;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("resumed child must read its owner's colour from its startup OSC 11 query");
    assert_eq!(text.matches(&marker).count(), 1);
}

#[tokio::test]
async fn direct_pending_resume_invalid_argv_retires_plan_and_requests_render() {
    let mut fixture = PendingFixture::new(1, "sleep 5");
    fixture
        .server
        .app
        .state
        .terminals
        .get_mut(&fixture.terminals[0])
        .unwrap()
        .pending_agent_resume_plan
        .as_mut()
        .unwrap()
        .argv
        .clear();
    let receivers = fixture.attach(7, 0, false);
    default_report(&mut fixture.server, 7, false, 30);
    default_report(&mut fixture.server, 7, true, 240);
    assert!(
        fixture
            .server
            .handle_server_event(ServerEvent::ClientShellHostTheme {
                client_id: 7,
                update: protocol::ClientHostThemeUpdate::Appearance(
                    protocol::ClientHostAppearance::Light
                ),
            }),
        "retiring a failed plan must request rendering even without a runtime"
    );
    assert!(!fixture.running(0));
    let terminal = fixture
        .server
        .app
        .state
        .terminals
        .get(&fixture.terminals[0])
        .unwrap();
    assert!(terminal.pending_agent_resume_plan.is_none());
    assert!(terminal.pending_resume_wait_deadline.is_none());
    assert!(!terminal.pending_resume_wait_for_owner);
    fixture.server.render_and_stream();
    assert!(!fixture.server.clients.contains_key(&7));
    assert!(receivers.control.try_iter().any(|bytes| matches!(
        read_server_message(bytes),
        ServerMessage::ServerShutdown { .. }
    )));
}

#[tokio::test]
async fn direct_pending_resume_waits_for_complete_report_and_uses_latest_resize() {
    let mut fixture = PendingFixture::new(1, "sleep 5");
    let receivers = fixture.attach(7, 0, false);
    assert!(!fixture.running(0));
    fixture.server.render_and_stream();
    receivers.assert_no_shutdown();
    assert!(fixture.server.clients.contains_key(&7));
    assert!(!fixture.running(0));

    fixture
        .server
        .handle_server_event(ServerEvent::ClientResize {
            client_id: 7,
            cols: 73,
            rows: 19,
            cell_width_px: 8,
            cell_height_px: 16,
            pixel_mouse: false,
        });
    assert!(
        !fixture.running(0),
        "resize must not end the observation wait"
    );
    default_report(&mut fixture.server, 7, false, 30);
    assert!(!fixture.running(0));
    default_report(&mut fixture.server, 7, true, 240);
    assert!(
        !fixture.running(0),
        "defaults are staged until the appearance marker"
    );
    finish_report(&mut fixture.server, 7);
    assert!(fixture.running(0));
    let id = &fixture.terminals[0];
    let runtime = fixture.server.app.terminal_runtimes.get(id).unwrap();
    assert_eq!(runtime.current_size(), (19, 73));
    assert_eq!(queried_background(&fixture.server, id).r, 240);
    let state = fixture.server.app.state.terminals.get(id).unwrap();
    assert!(state.pending_agent_resume_plan.is_none());
    assert!(state.pending_resume_wait_deadline.is_none());
    runtime.apply_desktop_terminal_appearance(context(60).theme, Some(HostAppearance::Dark));
    assert_eq!(
        queried_background(&fixture.server, id).r,
        240,
        "spawned direct runtime retains ownership"
    );
    fixture.server.render_and_stream();
    receivers.assert_no_shutdown();
    assert!(fixture.server.clients.contains_key(&7));
}

#[tokio::test]
async fn direct_pending_resume_wait_does_not_hide_a_missing_terminal() {
    let mut fixture = PendingFixture::new(1, "sleep 5");
    let receivers = fixture.attach(7, 0, false);
    fixture.server.render_and_stream();
    receivers.assert_no_shutdown();
    assert!(fixture.server.clients.contains_key(&7));
    fixture
        .server
        .app
        .state
        .terminals
        .remove(&fixture.terminals[0]);
    fixture.server.render_and_stream();
    let reasons: Vec<_> = receivers
        .control
        .try_iter()
        .filter_map(|bytes| match read_server_message(bytes) {
            ServerMessage::ServerShutdown { reason } => reason,
            _ => None,
        })
        .collect();
    assert!(
        reasons.iter().any(|reason| reason.contains("not found")),
        "missing terminal must end attach: {reasons:?}"
    );
    assert!(!fixture.server.clients.contains_key(&7));
}

#[tokio::test]
async fn direct_pending_resume_deadlines_are_independent_of_bulk_resume() {
    let mut fixture = PendingFixture::new(2, "sleep 5");
    let _first = fixture.attach(7, 0, false);
    let _second = fixture.attach(8, 1, false);
    let first_due = Instant::now() + Duration::from_secs(1);
    let second_due = first_due + Duration::from_secs(1);
    fixture
        .server
        .app
        .state
        .terminals
        .get_mut(&fixture.terminals[0])
        .unwrap()
        .pending_resume_wait_deadline = Some(first_due);
    fixture
        .server
        .app
        .state
        .terminals
        .get_mut(&fixture.terminals[1])
        .unwrap()
        .pending_resume_wait_deadline = Some(second_due);
    assert!(
        !fixture
            .server
            .app
            .start_pending_agent_resumes_at(second_due, true),
        "bulk launch cannot bypass direct-owner geometry/readiness"
    );
    assert_eq!(
        fixture.server.next_direct_resume_deadline(),
        Some(first_due)
    );
    fixture
        .server
        .handle_scheduled_tasks_headless(first_due, false);
    assert!(fixture.running(0));
    assert!(!fixture.running(1));
    assert_eq!(
        fixture.server.next_direct_resume_deadline(),
        Some(second_due)
    );
    fixture
        .server
        .handle_scheduled_tasks_headless(second_due, false);
    assert!(fixture.running(1));
    assert_eq!(fixture.server.next_direct_resume_deadline(), None);
}

#[tokio::test]
async fn direct_pending_resume_timeout_uses_only_target_local_context() {
    for remembered in [None, Some(context(220))] {
        let mut fixture = PendingFixture::new(1, "sleep 5");
        fixture.server.app.state.host_terminal_theme = context(87).theme;
        fixture.server.app.state.host_terminal_appearance = Some(HostAppearance::Dark);
        fixture
            .server
            .app
            .state
            .terminals
            .get_mut(&fixture.terminals[0])
            .unwrap()
            .query_context = remembered;
        let _receivers = fixture.attach(7, 0, false);
        let due = fixture.server.next_direct_resume_deadline().unwrap();
        assert!(
            !fixture.running(0),
            "old local context must not bypass fresh-owner wait"
        );
        fixture.server.handle_scheduled_tasks_headless(due, false);
        assert!(fixture.running(0));
        if let Some(known) = remembered {
            assert_eq!(
                queried_background(&fixture.server, &fixture.terminals[0]),
                known.theme.background.unwrap()
            );
        } else {
            let runtime = fixture
                .server
                .app
                .terminal_runtimes
                .get(&fixture.terminals[0])
                .unwrap();
            assert!(
                runtime.test_terminal_query(b"\x1b]11;?\x07").is_empty(),
                "unobserved background must not borrow the global colour or invent a reply"
            );
        }
    }
}

#[tokio::test]
async fn direct_pending_resume_early_input_reaches_only_its_target_exactly_once() {
    let command = "IFS= read -r first; IFS= read -r second; printf '\\nRESUME_INPUT:%s:%s\\n' \"$first\" \"$second\"; sleep 5";
    let mut fixture = PendingFixture::new(2, command);
    let _first = fixture.attach(7, 0, false);
    let _second = fixture.attach(8, 1, false);
    fixture
        .server
        .handle_server_event(ServerEvent::ClientInput {
            client_id: 7,
            data: Vec::new(),
        });
    assert!(!fixture.running(0), "empty input must not waive readiness");
    fixture
        .server
        .handle_server_event(ServerEvent::ClientInput {
            client_id: 7,
            data: b"alpha\r".to_vec(),
        });
    assert!(fixture.running(0));
    assert!(!fixture.running(1));
    fixture
        .server
        .handle_server_event(ServerEvent::ClientInput {
            client_id: 7,
            data: b"beta\r".to_vec(),
        });
    let result = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let text = fixture
                .server
                .app
                .terminal_runtimes
                .get(&fixture.terminals[0])
                .unwrap()
                .snapshot_history()
                .unwrap_or_default();
            if text.contains("RESUME_INPUT:alpha:beta") {
                break text;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
    let text = result.expect("resumed child must receive both input lines in order");
    assert_eq!(text.matches("RESUME_INPUT:alpha:beta").count(), 1);
    assert!(!fixture.running(1));
}

#[tokio::test]
async fn direct_pending_resume_takeover_rejects_old_reports_and_deadlines() {
    let mut fixture = PendingFixture::new(1, "sleep 5");
    let _old = fixture.attach(7, 0, false);
    let expired = Instant::now() - Duration::from_secs(1);
    fixture
        .server
        .app
        .state
        .terminals
        .get_mut(&fixture.terminals[0])
        .unwrap()
        .pending_resume_wait_deadline = Some(expired);
    let _new = fixture.attach(8, 0, true);
    let current_due = fixture.server.next_direct_resume_deadline().unwrap();
    assert!(current_due > expired);
    default_report(&mut fixture.server, 7, false, 30);
    default_report(&mut fixture.server, 7, true, 240);
    finish_report(&mut fixture.server, 7);
    fixture
        .server
        .handle_scheduled_tasks_headless(expired, false);
    assert!(!fixture.running(0));
    assert_eq!(
        fixture
            .server
            .terminal_attach_owners
            .get(fixture.terminals[0].as_str()),
        Some(&8)
    );
    default_report(&mut fixture.server, 8, false, 20);
    default_report(&mut fixture.server, 8, true, 230);
    finish_report(&mut fixture.server, 8);
    assert!(fixture.running(0));
    assert_eq!(
        queried_background(&fixture.server, &fixture.terminals[0]).r,
        230
    );
}

#[tokio::test]
async fn direct_pending_resume_takeover_never_launches_from_intermediate_desktop_context() {
    let mut fixture = PendingFixture::new(1, "sleep 5");
    let _desktop = connect_test_shell(&mut fixture.server, 21, 140, 45);
    let _old = fixture.attach(7, 0, false);
    default_report(&mut fixture.server, 21, false, 20);
    default_report(&mut fixture.server, 21, true, 80);
    finish_report(&mut fixture.server, 21);
    assert!(!fixture.running(0));
    assert!(
        fixture
            .server
            .desktop_appearance_for_terminal(fixture.terminals[0].as_str())
            .is_some(),
        "fixture needs a restorable same-tab desktop"
    );

    let _new = fixture.attach(8, 0, true);
    assert!(
        !fixture.running(0),
        "old-owner teardown must not temporarily resume under desktop colours"
    );
    assert!(!fixture.server.clients.contains_key(&7));
    assert_eq!(
        fixture
            .server
            .terminal_attach_owners
            .get(fixture.terminals[0].as_str()),
        Some(&8)
    );
    let pending = fixture
        .server
        .app
        .state
        .terminals
        .get(&fixture.terminals[0])
        .unwrap();
    assert!(pending.pending_resume_wait_for_owner);
    assert!(pending.pending_agent_resume_plan.is_some());

    default_report(&mut fixture.server, 8, false, 30);
    default_report(&mut fixture.server, 8, true, 230);
    finish_report(&mut fixture.server, 8);
    assert!(fixture.running(0));
    assert_eq!(
        queried_background(&fixture.server, &fixture.terminals[0]).r,
        230
    );
    assert_eq!(
        fixture
            .server
            .app
            .terminal_runtimes
            .get(&fixture.terminals[0])
            .unwrap()
            .current_size(),
        (28, 90)
    );
}

#[tokio::test]
async fn direct_pending_resume_cleared_or_failed_plan_ends_attach() {
    for failed_cleanup in [false, true] {
        let mut fixture = PendingFixture::new(1, "sleep 5");
        let receivers = fixture.attach(7, 0, false);
        fixture.server.render_and_stream();
        receivers.assert_no_shutdown();
        assert!(fixture.server.clients.contains_key(&7));
        let terminal = fixture
            .server
            .app
            .state
            .terminals
            .get_mut(&fixture.terminals[0])
            .unwrap();
        if failed_cleanup {
            terminal.clear_agent_runtime_identity_after_respawn();
        } else {
            terminal.pending_agent_resume_plan = None;
        }
        fixture.server.render_and_stream();
        assert!(
            !fixture.server.clients.contains_key(&7),
            "no live runtime or resume plan must not leave an endless waiting attach"
        );
        assert!(receivers.control.try_iter().any(|bytes| matches!(
            read_server_message(bytes),
            ServerMessage::ServerShutdown { .. }
        )));
        assert!(!fixture.running(0));
    }
}
