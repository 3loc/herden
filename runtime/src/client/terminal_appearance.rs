//! Colour observations belong to the viewing client, not to keyboard input.
//!
//! The stdin framer supplies complete control sequences (including bracketed
//! paste as one opaque chunk). Collect bounded colour state, then send defaults
//! and palette before the appearance marker so the server can publish one
//! coherent observation before notifying a subscribed application.

use std::time::{Duration, Instant};

use crate::protocol::{
    ClientHostAppearance, ClientHostColor, ClientHostDefaultColorKind, ClientHostThemeUpdate,
};
use crate::raw_input::RawInputEvent;

pub(super) fn host_theme_update(event: &RawInputEvent) -> Option<ClientHostThemeUpdate> {
    match event {
        RawInputEvent::HostDefaultColor { kind, color } => {
            Some(ClientHostThemeUpdate::DefaultColor {
                kind: match kind {
                    crate::terminal_theme::DefaultColorKind::Foreground => {
                        ClientHostDefaultColorKind::Foreground
                    }
                    crate::terminal_theme::DefaultColorKind::Background => {
                        ClientHostDefaultColorKind::Background
                    }
                },
                color: (*color).into(),
            })
        }
        RawInputEvent::HostPaletteColors { colors } => Some(ClientHostThemeUpdate::PaletteColors(
            colors
                .iter()
                .map(|(index, color)| (*index, (*color).into()))
                .collect(),
        )),
        RawInputEvent::HostColorSchemeChanged(appearance) => {
            Some(ClientHostThemeUpdate::Appearance(match appearance {
                crate::terminal_theme::HostAppearance::Dark => ClientHostAppearance::Dark,
                crate::terminal_theme::HostAppearance::Light => ClientHostAppearance::Light,
            }))
        }
        _ => None,
    }
}

pub(super) struct DirectTerminalAppearance {
    foreground: Option<ClientHostColor>,
    background: Option<ClientHostColor>,
    palette: std::collections::BTreeMap<u8, ClientHostColor>,
    appearance: Option<ClientHostAppearance>,
    publish_at: Option<Instant>,
    awaiting_defaults: bool,
    require_palette: bool,
}

impl Default for DirectTerminalAppearance {
    fn default() -> Self {
        Self {
            foreground: None,
            background: None,
            palette: Default::default(),
            appearance: None,
            publish_at: None,
            awaiting_defaults: true,
            require_palette: false,
        }
    }
}

impl DirectTerminalAppearance {
    pub(super) fn new(require_palette: bool) -> Self {
        Self {
            require_palette,
            ..Self::default()
        }
    }

    /// `Some` consumes a colour-only chunk; the bool requests a fresh palette
    /// after a mode notification. Non-colour input, especially paste, is left
    /// byte-for-byte intact. The deadline is never extended by sustained input.
    #[cfg(any(unix, test))]
    pub(super) fn consume(&mut self, data: &[u8], now: Instant) -> Option<bool> {
        let events = crate::raw_input::parse_raw_input_bytes_sync(data);
        if events.is_empty() {
            return None;
        }
        let updates = events
            .iter()
            .map(host_theme_update)
            .collect::<Option<Vec<_>>>()?;
        let mut query_palette = false;
        for update in updates {
            match update {
                ClientHostThemeUpdate::DefaultColor { kind, color } => match kind {
                    ClientHostDefaultColorKind::Foreground => self.foreground = Some(color),
                    ClientHostDefaultColorKind::Background => self.background = Some(color),
                },
                ClientHostThemeUpdate::PaletteColors(colors) => self.palette.extend(colors),
                ClientHostThemeUpdate::Appearance(appearance) => {
                    self.appearance = Some(appearance);
                    // A notification starts a new observation. Never combine
                    // its mode with defaults from the previous query round.
                    self.foreground = None;
                    self.background = None;
                    self.palette.clear();
                    self.awaiting_defaults = true;
                    self.publish_at = None;
                    query_palette = true;
                }
            }
        }
        if self.foreground.is_some()
            && self.background.is_some()
            && (!self.require_palette || self.palette.len() == 256)
        {
            self.awaiting_defaults = false;
        }
        if !self.awaiting_defaults {
            self.publish_at
                .get_or_insert(now + Duration::from_millis(50));
        }
        Some(query_palette)
    }

    pub(super) fn deadline(&self) -> Option<Instant> {
        self.publish_at
    }

    pub(super) fn take_due(&mut self, now: Instant) -> Vec<ClientHostThemeUpdate> {
        if !self.publish_at.is_some_and(|deadline| now >= deadline) {
            return Vec::new();
        }
        self.publish_at = None;
        let appearance = self.appearance.or_else(|| {
            self.background.map(|color| {
                match crate::terminal_theme::RgbColor::from(color).inferred_appearance() {
                    crate::terminal_theme::HostAppearance::Dark => ClientHostAppearance::Dark,
                    crate::terminal_theme::HostAppearance::Light => ClientHostAppearance::Light,
                }
            })
        });
        let Some(appearance) = appearance else {
            return Vec::new();
        };
        let mut updates = Vec::with_capacity(4);
        if let Some(color) = self.foreground {
            updates.push(ClientHostThemeUpdate::DefaultColor {
                kind: ClientHostDefaultColorKind::Foreground,
                color,
            });
        }
        if let Some(color) = self.background {
            updates.push(ClientHostThemeUpdate::DefaultColor {
                kind: ClientHostDefaultColorKind::Background,
                color,
            });
        }
        if !self.palette.is_empty() {
            updates.push(ClientHostThemeUpdate::PaletteColors(
                self.palette
                    .iter()
                    .map(|(&index, &color)| (index, color))
                    .collect(),
            ));
        }
        updates.push(ClientHostThemeUpdate::Appearance(appearance));
        updates
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direct_appearance_preserves_paste_and_keyboard_bytes() {
        let mut state = DirectTerminalAppearance::default();
        for bytes in [
            b"hello".as_slice(),
            b"\x1b[200~\x1b]11;rgb:ffff/ffff/ffff\x07\x1b[201~",
            b"\x1b[A",
        ] {
            assert_eq!(state.consume(bytes, Instant::now()), None);
        }
        assert!(state
            .take_due(Instant::now() + Duration::from_secs(1))
            .is_empty());
    }

    #[test]
    fn direct_appearance_publishes_split_palette_before_mode() {
        let now = Instant::now();
        let mut state = DirectTerminalAppearance::default();
        assert_eq!(state.consume(b"\x1b[?997;2n", now), Some(true));
        state.consume(b"\x1b]10;rgb:1111/1111/1111\x07", now);
        assert_eq!(
            state.consume(b"\x1b]11;rgb:ffff/ffff/ffff\x07", now),
            Some(false)
        );
        for bytes in [
            b"\x1b]4;1;rgb:ffff/0000/0000\x07",
            b"\x1b]4;2;rgb:0000/ffff/0000\x07",
        ] {
            assert_eq!(state.consume(bytes, now), Some(false));
        }
        assert!(state.take_due(now).is_empty());
        let updates = state.take_due(now + Duration::from_millis(51));
        assert!(matches!(
            updates.last(),
            Some(ClientHostThemeUpdate::Appearance(
                ClientHostAppearance::Light
            ))
        ));
        assert!(
            matches!(&updates[2], ClientHostThemeUpdate::PaletteColors(colors) if colors.len() == 2)
        );
        assert!(state.take_due(now + Duration::from_secs(1)).is_empty());
    }

    #[test]
    fn direct_appearance_handles_packet_splits_without_leaking_replies() {
        let wire = b"\x1b[?997;2n\x1b]10;rgb:1111/1111/1111\x07\x1b]11;rgb:ffff/ffff/ffff\x07";
        for split in 0..=wire.len() {
            let mut framer = crate::raw_input::RawInputByteFramer::for_host_input();
            framer.host_color_query_sent();
            framer.enable_host_color_scheme_change_tracking();
            let mut state = DirectTerminalAppearance::default();
            let now = Instant::now();
            for chunk in framer
                .push(&wire[..split])
                .into_iter()
                .chain(framer.push(&wire[split..]))
            {
                assert!(
                    state.consume(&chunk, now).is_some(),
                    "split {split}: {chunk:?}"
                );
            }
            assert!(matches!(
                state.take_due(now + Duration::from_secs(1)).last(),
                Some(ClientHostThemeUpdate::Appearance(
                    ClientHostAppearance::Light
                ))
            ));
        }
    }

    #[test]
    fn direct_appearance_waits_for_fresh_defaults_after_delayed_mode_change() {
        let now = Instant::now();
        let mut state = DirectTerminalAppearance::default();
        state.consume(b"\x1b[?997;1n", now);
        state.consume(b"\x1b]10;rgb:eeee/eeee/eeee\x07", now);
        state.consume(b"\x1b]11;rgb:1111/1111/1111\x07", now);
        assert!(!state.take_due(now + Duration::from_secs(1)).is_empty());

        let switched = now + Duration::from_secs(2);
        state.consume(b"\x1b[?997;2n", switched);
        assert_eq!(state.deadline(), None);
        assert!(state.take_due(switched + Duration::from_secs(1)).is_empty());
        state.consume(
            b"\x1b]11;rgb:ffff/ffff/ffff\x07",
            switched + Duration::from_secs(2),
        );
        assert!(state.take_due(switched + Duration::from_secs(3)).is_empty());
        let ready = switched + Duration::from_secs(4);
        state.consume(b"\x1b]10;rgb:2222/2222/2222\x07", ready);
        assert_eq!(state.deadline(), Some(ready + Duration::from_millis(50)));
        let updates = state.take_due(ready + Duration::from_millis(50));
        assert!(matches!(
            updates.first(),
            Some(ClientHostThemeUpdate::DefaultColor {
                kind: ClientHostDefaultColorKind::Foreground,
                color: ClientHostColor {
                    r: 34,
                    g: 34,
                    b: 34
                },
            })
        ));
        assert!(matches!(
            updates.last(),
            Some(ClientHostThemeUpdate::Appearance(
                ClientHostAppearance::Light
            ))
        ));
    }

    #[test]
    fn direct_appearance_does_not_publish_a_new_mode_with_a_partial_palette() {
        let now = Instant::now();
        let mut state = DirectTerminalAppearance::new(true);
        state.consume(b"\x1b[?997;2n", now);
        state.consume(b"\x1b]10;rgb:2222/2222/2222\x07", now);
        state.consume(b"\x1b]11;rgb:ffff/ffff/ffff\x07", now);
        for index in 0..255 {
            state.consume(
                format!("\x1b]4;{index};rgb:aaaa/bbbb/cccc\x07").as_bytes(),
                now,
            );
        }
        assert_eq!(state.deadline(), None);
        assert!(state.take_due(now + Duration::from_secs(1)).is_empty());
        let ready = now + Duration::from_secs(2);
        state.consume(b"\x1b]4;255;rgb:aaaa/bbbb/cccc\x07", ready);
        let updates = state.take_due(ready + Duration::from_millis(50));
        assert!(
            matches!(&updates[2], ClientHostThemeUpdate::PaletteColors(colors) if colors.len() == 256)
        );
    }
}
