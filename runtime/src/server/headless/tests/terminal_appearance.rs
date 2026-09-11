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

fn report_background(server: &mut HeadlessServer, client_id: u64, value: u8) {
    report(
        server,
        client_id,
        protocol::ClientHostThemeUpdate::DefaultColor {
            kind: protocol::ClientHostDefaultColorKind::Background,
            color: protocol::ClientHostColor {
                r: value,
                g: value,
                b: value,
            },
        },
    );
}

fn add_appearance_test_tab(server: &mut HeadlessServer) -> (crate::terminal::TerminalId, String) {
    let workspace = &mut server.app.state.workspaces[0];
    let tab = workspace.test_add_tab(Some("second"));
    let terminal = workspace
        .terminal_id(workspace.tabs[tab].root_pane)
        .expect("terminal")
        .clone();
    server.app.state.ensure_test_terminals();
    server.app.terminal_runtimes.insert(
        terminal.clone(),
        crate::terminal::TerminalRuntime::test_with_screen_bytes(80, 24, b""),
    );
    (
        terminal,
        server.app.public_tab_id(0, tab).expect("public tab"),
    )
}

#[test]
fn desktop_appearance_stays_with_each_currently_controlled_tab() {
    with_terminal_session_test_server(|server, first, _, _| {
        server.app.state.active = Some(0);
        server.app.state.mode = crate::app::Mode::Terminal;
        let (second, second_tab) = add_appearance_test_tab(server);
        let _first_connection = connect_test_shell(server, 21, 80, 24);
        let _second_connection = connect_test_shell(server, 22, 80, 24);
        assert!(server.focus_shell_client_on_tab(22, &second_tab));
        server.claim_shell_tab_geometry(22, false);
        report_background(server, 21, 10);
        report_background(server, 22, 240);
        assert_eq!(
            background(server.app.terminal_runtimes.get(&first).unwrap()).r,
            10
        );
        assert_eq!(
            background(server.app.terminal_runtimes.get(&second).unwrap()).r,
            240
        );
        server.foreground_client_id = Some(21);
        server.sync_foreground_client_state();
        assert_eq!(
            background(server.app.terminal_runtimes.get(&second).unwrap()).r,
            240
        );
    });
}

#[test]
fn direct_appearance_retains_last_context_without_a_current_desktop_viewer() {
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
            RgbColor {
                r: 240,
                g: 240,
                b: 240
            }
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
        server
            .app
            .terminal_runtimes
            .get(&other_id)
            .expect("other runtime")
            .apply_desktop_terminal_appearance(
                TerminalTheme {
                    background: Some(dark),
                    ..Default::default()
                },
                Some(HostAppearance::Dark),
            );
        attach(server, 7, &terminal_name, false);
        assert!(report_light(server, 7));
        assert_eq!(
            background(server.app.terminal_runtimes.get(&terminal_id).unwrap()).r,
            240
        );
        assert_eq!(
            background(server.app.terminal_runtimes.get(&other_id).unwrap()),
            dark
        );
    });
}

#[test]
fn direct_detach_restores_its_own_desktop_controller_not_global_foreground() {
    with_terminal_session_test_server(|server, first, terminal_name, _| {
        server.app.state.active = Some(0);
        server.app.state.mode = crate::app::Mode::Terminal;
        let (second, second_tab) = add_appearance_test_tab(server);
        let _first_connection = connect_test_shell(server, 21, 80, 24);
        let _second_connection = connect_test_shell(server, 22, 80, 24);
        server.focus_shell_client_on_tab(22, &second_tab);
        server.claim_shell_tab_geometry(22, false);
        report_background(server, 21, 10);
        report_background(server, 22, 30);
        attach(server, 7, &terminal_name, false);
        assert!(report_light(server, 7));
        report_background(server, 21, 20);
        assert_eq!(
            background(server.app.terminal_runtimes.get(&first).unwrap()).r,
            240
        );
        server.foreground_client_id = Some(22);
        server.sync_foreground_client_state();
        server.handle_server_event(ServerEvent::ClientDisconnected { client_id: 7 });
        assert_eq!(
            background(server.app.terminal_runtimes.get(&first).unwrap()).r,
            20
        );
        assert_eq!(
            background(server.app.terminal_runtimes.get(&second).unwrap()).r,
            30
        );
    });
}

#[test]
fn desktop_disconnect_and_deactivation_select_a_same_tab_replacement() {
    for disconnect in [true, false] {
        with_terminal_session_test_server(|server, first, _, _| {
            server.app.state.active = Some(0);
            server.app.state.mode = crate::app::Mode::Terminal;
            let first_tab = server.app.public_tab_id(0, 0).unwrap();
            let (second, second_tab) = add_appearance_test_tab(server);
            let _a = connect_test_shell(server, 21, 80, 24);
            let _b = connect_test_shell(server, 22, 80, 24);
            let _c = connect_test_shell(server, 23, 80, 24);
            server.focus_shell_client_on_tab(22, &first_tab);
            server.focus_shell_client_on_tab(23, &second_tab);
            server.claim_shell_tab_geometry(21, false);
            server.claim_shell_tab_geometry(23, false);
            report_background(server, 21, 10);
            report_background(server, 22, 20);
            report_background(server, 23, 240);
            assert_eq!(
                background(server.app.terminal_runtimes.get(&first).unwrap()).r,
                10
            );
            if disconnect {
                server.handle_server_event(ServerEvent::ClientDisconnected { client_id: 21 });
            } else {
                server.set_client_shell_surface_active(21, false);
            }
            assert_eq!(server.tab_geometry_controllers.get(&first_tab), Some(&22));
            assert_eq!(
                background(server.app.terminal_runtimes.get(&first).unwrap()).r,
                20
            );
            assert_eq!(
                background(server.app.terminal_runtimes.get(&second).unwrap()).r,
                240
            );
        });
    }
}

#[test]
fn desktop_reports_cannot_recolour_a_tab_the_controller_has_left() {
    with_terminal_session_test_server(|server, first, _, _| {
        server.app.state.active = Some(0);
        server.app.state.mode = crate::app::Mode::Terminal;
        let first_tab = server.app.public_tab_id(0, 0).unwrap();
        let (_, second_tab) = add_appearance_test_tab(server);
        let _a = connect_test_shell(server, 21, 80, 24);
        report_background(server, 21, 10);
        server.focus_shell_client_on_tab(21, &second_tab);
        server.claim_shell_tab_geometry(21, false);
        report_background(server, 21, 240);
        assert_eq!(
            background(server.app.terminal_runtimes.get(&first).unwrap()).r,
            10
        );
        let _b = connect_test_shell(server, 22, 80, 24);
        server.focus_shell_client_on_tab(22, &first_tab);
        server.claim_unowned_shell_tab_geometry(22, false);
        report_background(server, 22, 20);
        assert_eq!(server.tab_geometry_controllers.get(&first_tab), Some(&22));
        assert_eq!(
            background(server.app.terminal_runtimes.get(&first).unwrap()).r,
            20
        );
    });
}

#[test]
fn remaining_desktop_viewer_report_reclaims_a_vacated_tab() {
    with_terminal_session_test_server(|server, first, _, _| {
        server.app.state.active = Some(0);
        server.app.state.mode = crate::app::Mode::Terminal;
        let first_tab = server.app.public_tab_id(0, 0).unwrap();
        let (_, second_tab) = add_appearance_test_tab(server);
        let _a = connect_test_shell(server, 21, 80, 24);
        let _b = connect_test_shell(server, 22, 80, 24);
        server.focus_shell_client_on_tab(22, &first_tab);
        server.claim_shell_tab_geometry(21, false);
        report_background(server, 21, 10);
        server.focus_shell_client_on_tab(21, &second_tab);
        server.claim_shell_tab_geometry(21, false);
        report_background(server, 22, 20);
        assert_eq!(server.tab_geometry_controllers.get(&first_tab), Some(&22));
        assert_eq!(
            background(server.app.terminal_runtimes.get(&first).unwrap()).r,
            20
        );
    });
}
