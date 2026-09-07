use qrcode::types::Color;
use qrcode::QrCode;

pub(crate) fn render(text: &str) -> Result<String, String> {
    let code =
        QrCode::new(text.as_bytes()).map_err(|error| format!("QR encoding failed: {error}"))?;
    let width = code.width();
    let quiet = 2_usize;
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
}
