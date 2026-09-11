use super::*;
use crate::terminal_theme::{HostAppearance, TerminalQueryContext, TerminalTheme};

impl HeadlessServer {
    pub(super) fn is_current_shell_appearance_controller(
        &self,
        client_id: u64,
        tab_id: &str,
    ) -> bool {
        self.tab_geometry_controllers.get(tab_id) == Some(&client_id)
            && self
                .clients
                .get(&client_id)
                .is_some_and(|client| client.is_active_shell_client() && client.writer.is_some())
            && self.shell_tab_id_for_client(client_id).as_deref() == Some(tab_id)
    }

    // Reports and ownership transitions are infrequent events. Do not call this
    // from render, input, or the single-client all-tabs geometry fast path.
    pub(super) fn apply_shell_client_terminal_appearance(&mut self, client_id: u64) -> bool {
        let Some(tab_id) = self.shell_tab_id_for_client(client_id) else {
            return false;
        };
        if !self.is_current_shell_appearance_controller(client_id, &tab_id) {
            return false;
        }
        let Some((workspace_index, tab_index)) = self.app.parse_tab_id(&tab_id) else {
            return false;
        };
        let Some(client) = self.clients.get(&client_id) else {
            return false;
        };
        let theme = client.host_terminal_theme;
        let appearance = client.host_terminal_appearance;
        let panes: Vec<_> = self.app.state.workspaces[workspace_index].tabs[tab_index]
            .panes
            .iter()
            .map(|(pane_id, pane)| (*pane_id, pane.attached_terminal_id.clone()))
            .collect();
        for (pane_id, terminal_id) in panes {
            if self
                .app
                .state
                .direct_attach_resize_locks
                .contains(&terminal_id)
            {
                continue;
            }
            if let Some(terminal) = self.app.state.terminals.get_mut(&terminal_id) {
                terminal.query_context = Some(TerminalQueryContext { theme, appearance });
            }
            if let Some(runtime) = self.app.state.runtime_for_pane_in_workspace(
                &self.app.terminal_runtimes,
                workspace_index,
                pane_id,
            ) {
                runtime.apply_desktop_terminal_appearance(theme, appearance);
            }
        }
        if self.popup_owner_tab_id.as_deref() == Some(tab_id.as_str()) {
            if let Some(runtime) = self
                .app
                .state
                .popup_pane
                .as_ref()
                .and_then(|popup| self.app.terminal_runtimes.get(&popup.terminal_id))
            {
                runtime.apply_desktop_terminal_appearance(theme, appearance);
            }
        }
        true
    }

    pub(super) fn desktop_appearance_for_terminal(
        &self,
        terminal_id: &str,
    ) -> Option<(TerminalTheme, Option<HostAppearance>)> {
        let (client_id, target) = self.shell_geometry_controller_for_terminal(terminal_id)?;
        let tab_id = self
            .app
            .public_tab_id(target.workspace_index, target.tab_index)?;
        if !self.is_current_shell_appearance_controller(client_id, &tab_id) {
            return None;
        }
        let client = self.clients.get(&client_id)?;
        Some((client.host_terminal_theme, client.host_terminal_appearance))
    }
}
