use std::io::{self, IsTerminal};
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode};

/// Own terminal input only while the pairing code is displayed.
pub(super) struct PairingInput {
    interactive: bool,
}

impl PairingInput {
    pub(super) fn new() -> io::Result<Self> {
        let interactive = io::stdin().is_terminal();
        if interactive {
            enable_raw_mode()?;
        }
        Ok(Self { interactive })
    }

    pub(super) fn poll_cancel(&self, timeout: Duration) -> io::Result<Option<i32>> {
        if !self.interactive {
            std::thread::sleep(timeout);
            return Ok(None);
        }
        if !event::poll(timeout)? {
            return Ok(None);
        }
        let Event::Key(key) = event::read()? else {
            return Ok(None);
        };
        if key.kind == KeyEventKind::Release {
            return Ok(None);
        }
        if key.modifiers == KeyModifiers::NONE
            && matches!(key.code, KeyCode::Char('q') | KeyCode::Esc)
        {
            return Ok(Some(0));
        }
        if key.modifiers.contains(KeyModifiers::CONTROL)
            && matches!(key.code, KeyCode::Char('c' | 'C'))
        {
            return Ok(Some(130));
        }
        Ok(None)
    }
}

impl Drop for PairingInput {
    fn drop(&mut self) {
        if self.interactive {
            let _ = disable_raw_mode();
        }
    }
}
