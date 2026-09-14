use super::*;

/// A single text row keeps the product visible in every terminal.
pub(super) fn render_header(buffer: &mut Buffer, area: Rect, config: &ClientShellConfig) -> Rect {
    let width = area.width.saturating_sub(1);
    if width < 8 || area.height == 0 {
        return area;
    }
    super::render::put_text(
        buffer,
        area.x,
        area.y,
        width,
        "[herden]",
        Style::default()
            .fg(config.palette.accent)
            .bg(config.palette.sidebar_bg)
            .add_modifier(Modifier::BOLD),
    );
    Rect::new(area.x, area.y + 1, area.width, area.height - 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_keeps_herden_identity_visible_and_reserves_one_row() {
        let config = ClientShellConfig::from_config(&Config::default());
        let area = Rect::new(0, 0, 20, 4);
        let mut buffer = Buffer::empty(area);

        let remaining = render_header(&mut buffer, area, &config);

        assert_eq!(remaining, Rect::new(0, 1, 20, 3));
        let rendered = (0..8).map(|x| buffer[(x, 0)].symbol()).collect::<String>();
        assert_eq!(rendered, "[herden]");
    }
}
