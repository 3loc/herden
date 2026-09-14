use super::*;

impl HeadlessServer {
    pub(super) fn terminal_resume_is_pending(&self, terminal_id: &str) -> bool {
        self.app
            .state
            .terminals
            .get(terminal_id)
            .is_some_and(|terminal| terminal.pending_agent_resume_plan.is_some())
    }

    pub(super) fn next_direct_resume_deadline(&self) -> Option<Instant> {
        self.app
            .state
            .direct_attach_resize_locks
            .iter()
            .filter_map(|id| self.app.state.terminals.get(id))
            .filter(|terminal| terminal.pending_agent_resume_plan.is_some())
            .filter_map(|terminal| terminal.pending_resume_wait_deadline)
            .min()
    }

    pub(super) fn start_due_direct_resumes(&mut self, now: Instant) -> bool {
        // Visit only directly owned terminals, without snapshots or parser locks.
        // The common live-terminal case allocates nothing.
        let owners: Vec<_> = self
            .app
            .state
            .direct_attach_resize_locks
            .iter()
            .filter_map(|id| {
                let terminal = self.app.state.terminals.get(id)?;
                if terminal.pending_agent_resume_plan.is_none()
                    || !terminal
                        .pending_resume_wait_deadline
                        .is_some_and(|end| now >= end)
                {
                    return None;
                }
                self.terminal_attach_owners.get(id.as_str()).copied()
            })
            .collect();
        let mut changed = false;
        for client_id in owners {
            changed |= self.start_direct_resume(client_id, true);
        }
        changed
    }

    // Explicit input may end only its target's observation wait. This prevents
    // dropped keystrokes without buffering/replaying them or borrowing a palette
    // from another terminal. Resize, hover and reports never take this fallback.
    pub(super) fn start_direct_resume(&mut self, client_id: u64, allow_fallback: bool) -> bool {
        if self.handoff_in_progress {
            return false;
        }
        let Some(client) = self.clients.get(&client_id) else {
            return false;
        };
        let ClientConnectionMode::TerminalAttach { terminal_id } = &client.mode else {
            return false;
        };
        if self.terminal_attach_owners.get(terminal_id) != Some(&client_id) {
            return false;
        }
        let Some(terminal) = self.app.state.terminals.get(terminal_id.as_str()) else {
            return false;
        };
        if terminal.pending_agent_resume_plan.is_none() {
            return false;
        }
        let id = terminal.id.clone();
        let (cols, rows) = client.terminal_size;
        let cell_size = client.cell_size;
        let started =
            self.app
                .start_pending_agent_resume_for_terminal(&id, rows, cols, allow_fallback);
        if started {
            if let Some(runtime) = self.app.terminal_runtimes.get(&id) {
                runtime.resize(rows, cols, cell_size.width_px, cell_size.height_px);
            }
        }
        started
    }
}
