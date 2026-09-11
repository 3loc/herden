use super::*;
use crate::terminal_theme::{HostAppearance, RgbColor, TerminalTheme};

fn report(
    server: &mut HeadlessServer,
    client_id: u64,
    update: protocol::ClientHostThemeUpdate,
) -> bool {
    server.handle_server_event(ServerEvent::ClientShellHostTheme { client_id, update })
}

fn background(runtime: &crate::terminal::TerminalRuntime) -> RgbColor {
    let response = runtime.test_terminal_query(b"\x1b]11;?\x07");
    let text = std::str::from_utf8(&response[0]).expect("query response");
    crate::terminal_theme::parse_default_color_response(text)
        .expect("colour response")
        .1
}

fn attach(server: &mut HeadlessServer, client_id: u64, terminal_id: &str, takeover: bool) {
    connect_pending_terminal_client(server, client_id);
    assert!(
        server.handle_server_event(ServerEvent::ClientControlTerminal {
            client_id,
            target: terminal_id.to_owned(),
            takeover,
        })
    );
}

fn report_light(server: &mut HeadlessServer, client_id: u64) -> bool {
    assert!(!report(
        server,
        client_id,
        protocol::ClientHostThemeUpdate::DefaultColor {
            kind: protocol::ClientHostDefaultColorKind::Background,
            color: protocol::ClientHostColor {
                r: 240,
                g: 240,
                b: 240
            },
        }
    ));
    report(
        server,
        client_id,
        protocol::ClientHostThemeUpdate::Appearance(protocol::ClientHostAppearance::Light),
    )
}

#[test]
fn direct_appearance_is_scoped_and_survives_desktop_updates() {
    with_terminal_session_test_server(|server, terminal_id, terminal_name, _| {
        let dark = RgbColor {
            r: 10,
            g: 10,
            b: 10,
        };
        server.app.set_host_terminal_theme(TerminalTheme {
            background: Some(dark),
            ..Default::default()
        });
        server
            .app
            .set_host_terminal_appearance_state(Some(HostAppearance::Dark), true);
        attach(server, 7, &terminal_name, false);
        assert!(report_light(server, 7));
        let runtime = server
            .app
            .terminal_runtimes
            .get(&terminal_id)
            .expect("runtime");
        assert_eq!(
            background(runtime),
            RgbColor {
                r: 240,
                g: 240,
                b: 240
            }
        );
        assert_eq!(server.app.state.host_terminal_theme.background, Some(dark));

        let newer_dark = RgbColor {
            r: 20,
            g: 20,
            b: 20,
        };
        server.app.set_host_terminal_theme(TerminalTheme {
            background: Some(newer_dark),
            ..Default::default()
        });
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&terminal_id)
                    .expect("runtime")
            ),
            RgbColor {
                r: 240,
                g: 240,
                b: 240
            }
        );
        server.handle_server_event(ServerEvent::ClientDisconnected { client_id: 7 });
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&terminal_id)
                    .expect("runtime")
            ),
            newer_dark
        );
    });
}

#[test]
fn direct_appearance_only_publishes_complete_batches_even_when_mode_is_unchanged() {
    with_terminal_session_test_server(|server, terminal_id, terminal_name, _| {
        attach(server, 7, &terminal_name, false);
        assert!(report_light(server, 7));
        let next = protocol::ClientHostColor {
            r: 250,
            g: 250,
            b: 250,
        };
        report(
            server,
            7,
            protocol::ClientHostThemeUpdate::DefaultColor {
                kind: protocol::ClientHostDefaultColorKind::Background,
                color: next,
            },
        );
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&terminal_id)
                    .expect("runtime")
            ),
            RgbColor {
                r: 240,
                g: 240,
                b: 240
            }
        );
        assert!(report(
            server,
            7,
            protocol::ClientHostThemeUpdate::Appearance(protocol::ClientHostAppearance::Light)
        ));
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&terminal_id)
                    .expect("runtime")
            ),
            next.into()
        );
    });
}

#[test]
fn direct_appearance_ignores_observers_and_stale_takeover_reports() {
    with_terminal_session_test_server(|server, terminal_id, terminal_name, _| {
        attach(server, 7, &terminal_name, false);
        assert!(report_light(server, 7));
        connect_pending_terminal_client(server, 8);
        assert!(
            server.handle_server_event(ServerEvent::ClientObserveTerminal {
                client_id: 8,
                target: terminal_name.clone(),
            })
        );
        assert!(!report_light(server, 8));

        attach(server, 9, &terminal_name, true);
        assert!(report_light(server, 9));
        assert!(!report(
            server,
            7,
            protocol::ClientHostThemeUpdate::Appearance(protocol::ClientHostAppearance::Dark)
        ));
        server.handle_server_event(ServerEvent::ClientDisconnected { client_id: 7 });
        assert_eq!(server.terminal_attach_owners.get(&terminal_name), Some(&9));
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&terminal_id)
                    .expect("runtime")
            ),
            RgbColor {
                r: 240,
                g: 240,
                b: 240
            }
        );
    });
}

#[test]
fn direct_appearance_cannot_overwrite_another_terminal() {
    with_terminal_session_test_server(|server, terminal_id, terminal_name, _| {
        let other_workspace = crate::workspace::Workspace::test_new("other");
        let other_id = other_workspace
            .terminal_id(other_workspace.tabs[0].root_pane)
            .expect("terminal")
            .clone();
        server.app.state.workspaces.push(other_workspace);
        server.app.state.ensure_test_terminals();
        server.app.terminal_runtimes.insert(
            other_id.clone(),
            crate::terminal::TerminalRuntime::test_with_screen_bytes(80, 24, b""),
        );
        let dark = RgbColor {
            r: 12,
            g: 12,
            b: 12,
        };
        server.app.set_host_terminal_theme(TerminalTheme {
            background: Some(dark),
            ..Default::default()
        });
        attach(server, 7, &terminal_name, false);
        assert!(report_light(server, 7));
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&terminal_id)
                    .expect("runtime")
            ),
            RgbColor {
                r: 240,
                g: 240,
                b: 240
            }
        );
        assert_eq!(
            background(
                server
                    .app
                    .terminal_runtimes
                    .get(&other_id)
                    .expect("other runtime")
            ),
            dark
        );
    });
}
