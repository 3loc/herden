use qrcode::types::Color;
use qrcode::{EcLevel, QrCode};

pub(crate) fn render(text: &str) -> Result<String, String> {
    // Pairing Codes are displayed on a clean terminal rather than printed on a
    // damaged label. Level L plus the spec-required quiet zone gives the phone
    // a smaller symbol without changing any credential material.
    let code = QrCode::with_error_correction_level(text.as_bytes(), EcLevel::L)
        .map_err(|error| format!("QR encoding failed: {error}"))?;
    let width = code.width();
    let quiet = 4_usize;
    let total = width + quiet * 2;
    let mut output = String::new();

    for y in (0..total).step_by(2) {
        output.push_str("\x1b[30;47m");
        for x in 0..total {
            let top = is_dark(&code, x, y, quiet);
            let bottom = is_dark(&code, x, y + 1, quiet);
            match (top, bottom) {
                (true, true) => output.push_str("\x1b[40m "),
                (true, false) => output.push_str("\x1b[30;47m▀"),
                (false, true) => output.push_str("\x1b[30;47m▄"),
                (false, false) => output.push_str("\x1b[47m "),
            }
        }
        output.push_str("\x1b[0m\n");
    }
    Ok(output)
}

fn is_dark(code: &QrCode, x: usize, y: usize, quiet: usize) -> bool {
    let width = code.width();
    let Some(module_x) = x.checked_sub(quiet) else {
        return false;
    };
    let Some(module_y) = y.checked_sub(quiet) else {
        return false;
    };
    module_x < width && module_y < width && code[(module_x, module_y)] == Color::Dark
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qr_rendering_has_explicit_contrast_and_reset_sequences() {
        let rendered = render("HERDR-PAIR:1:test").expect("QR render");
        assert!(rendered.starts_with("\x1b[30;47m"));
        assert!(rendered.ends_with("\x1b[0m\n"));
        assert!(rendered.lines().count() > 10);
    }

    #[test]
    fn representative_compact_code_renders_within_49_by_25_cells() {
        let vectors: serde_json::Value = serde_json::from_str(include_str!(
            "../../../plugin/test-vectors/pairing-code-v2.json"
        ))
        .expect("valid shared pairing vectors");
        let code = vectors["valid"][0]["code"]
            .as_str()
            .expect("compact Pairing Code");
        let qr =
            QrCode::with_error_correction_level(code.as_bytes(), EcLevel::L).expect("QR encoding");
        let rendered = render(code).expect("QR render");

        assert_eq!(qr.width(), 41);
        assert_eq!(rendered.lines().count(), 25);
        // ANSI escapes do not occupy terminal cells; the renderer emits one
        // glyph or space per module plus the eight-cell quiet zone.
        assert_eq!(qr.width() + 8, 49);
    }
}
