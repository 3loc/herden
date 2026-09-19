use std::io;
use std::net::IpAddr;

use crate::glasses::{self, Settings};

pub(super) fn run_glasses_command(args: &[String]) -> io::Result<i32> {
    match args.first().map(String::as_str) {
        Some("enable") => enable(&args[1..]),
        Some("disable") => disable(&args[1..]),
        Some("status") => status(&args[1..]),
        Some("token") => token(&args[1..]),
        Some("package") => package(&args[1..]),
        Some("help" | "--help" | "-h") | None => {
            help();
            Ok(0)
        }
        _ => {
            help();
            Ok(2)
        }
    }
}

fn enable(args: &[String]) -> io::Result<i32> {
    let mut bind = None;
    let mut port = None;
    let mut controls = None;
    let mut control_mode_seen = false;
    let mut reconfigure = false;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--bind" => {
                index += 1;
                bind = args.get(index).cloned();
                if bind.is_none() {
                    return usage_enable();
                }
            }
            "--port" => {
                index += 1;
                port = args.get(index).and_then(|raw| raw.parse::<u16>().ok());
                if port.is_none() {
                    return usage_enable();
                }
            }
            "--controls" => {
                if control_mode_seen {
                    return usage_enable();
                }
                control_mode_seen = true;
                controls = Some(true);
            }
            "--read-only" => {
                if control_mode_seen {
                    return usage_enable();
                }
                control_mode_seen = true;
                controls = Some(false);
            }
            "--reconfigure" => reconfigure = true,
            _ => return usage_enable(),
        }
        index += 1;
    }
    let existing = glasses::load_settings()?;
    let selected_bind = match bind {
        Some(bind) => bind,
        None => existing
            .as_ref()
            .map(|settings| settings.bind.clone())
            .unwrap_or(
                glasses::choose_tailnet_address()
                    .map_err(io::Error::other)?
                    .to_string(),
            ),
    };
    let address: IpAddr = selected_bind.parse().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "--bind must be an address belonging to this Host",
        )
    })?;
    glasses::validate_bind(&address.to_string()).map_err(io::Error::other)?;
    let requested_port = port.unwrap_or_else(|| {
        existing
            .as_ref()
            .map(|settings| settings.port)
            .unwrap_or(glasses::DEFAULT_PORT)
    });
    if let Some(current) = &existing {
        let changes_bind = current.bind != address.to_string() || current.port != requested_port;
        if changes_bind && current.enabled && !reconfigure {
            eprintln!("the HUD is already enabled at {}:{}; use --reconfigure with an explicit --bind/--port to change it", current.bind, current.port);
            return Ok(2);
        }
    }
    let settings = Settings {
        enabled: true,
        bind: address.to_string(),
        port: requested_port,
        controls: controls.unwrap_or_else(|| {
            existing
                .as_ref()
                .map(|settings| settings.controls)
                .unwrap_or(false)
        }),
    };
    let new_token = existing
        .is_none()
        .then(glasses::save_new_credential)
        .transpose()?;
    glasses::save_settings(&settings)?;
    println!(
        "Herden HUD enabled at http://{}:{} ({}) for this {} session.",
        settings.bind,
        settings.port,
        if settings.controls {
            "controls enabled"
        } else {
            "read-only"
        },
        crate::session::active_name().unwrap_or_else(|| "default".into())
    );
    println!("The endpoint is private-network HTTP. LAN traffic is not encrypted. The Even G2 package, iPhone HTTP/SSE behaviour, whitelist semantics, and background/wake behaviour remain hardware-gated; see docs/guides/glasses.md before relying on it.");
    if let Some(token) = new_token {
        print_credential(&token);
    }
    Ok(0)
}

fn disable(args: &[String]) -> io::Result<i32> {
    if !args.is_empty() {
        eprintln!("usage: herden glasses disable");
        return Ok(2);
    }
    let Some(mut settings) = glasses::load_settings()? else {
        println!("Herden HUD is already disabled.");
        return Ok(0);
    };
    settings.enabled = false;
    glasses::save_settings(&settings)?;
    println!(
        "Herden HUD disabled. Agents keep running; the saved private-network setup is retained."
    );
    Ok(0)
}

fn status(args: &[String]) -> io::Result<i32> {
    if !args.is_empty() {
        eprintln!("usage: herden glasses status");
        return Ok(2);
    }
    let Some(settings) = glasses::load_settings()? else {
        println!("Herden HUD: disabled");
        return Ok(0);
    };
    println!(
        "Herden HUD: {}",
        if settings.enabled {
            "enabled"
        } else {
            "disabled"
        }
    );
    println!("address: {}:{}", settings.bind, settings.port);
    println!(
        "controls: {}",
        if settings.controls {
            "enabled"
        } else {
            "read-only"
        }
    );
    match std::fs::read_to_string(crate::session::data_dir().join("glasses-status.json"))
        .ok()
        .and_then(|content| serde_json::from_str::<serde_json::Value>(&content).ok())
    {
        Some(status) => {
            println!(
                "listener: {}",
                status
                    .get("state")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("unknown")
            );
            if let Some(detail) = status.get("detail").and_then(serde_json::Value::as_str) {
                println!("detail: {detail}");
            }
        }
        None if settings.enabled => {
            println!("listener: waiting for the running Host to load this setting")
        }
        None => println!("listener: disabled"),
    }
    println!("package: no hardware-verified Even package is available yet");
    Ok(0)
}

fn token(args: &[String]) -> io::Result<i32> {
    match args {
        [command] if command == "show" => show_token(),
        [command] if command == "rotate" => rotate(),
        _ => {
            eprintln!("usage: herden glasses token <show|rotate>");
            Ok(2)
        }
    }
}

fn show_token() -> io::Result<i32> {
    if glasses::load_settings()?.is_none() {
        eprintln!("Herden HUD is not configured; run `herden glasses enable` first.");
        return Ok(1);
    }
    print_credential(&glasses::credential_token()?);
    Ok(0)
}

fn rotate() -> io::Result<i32> {
    if glasses::load_settings()?.is_none() {
        eprintln!("Herden HUD is not configured; run `herden glasses enable` first.");
        return Ok(1);
    }
    let token = glasses::save_new_credential()?;
    println!("HUD credential rotated. Existing event streams are closed within one second.");
    print_credential(&token);
    Ok(0)
}

fn print_credential(token: &str) {
    println!("HUD credential (shown because you explicitly enabled, showed, or rotated it; `herden glasses status` never prints it):");
    println!("{token}");
}

fn package(args: &[String]) -> io::Result<i32> {
    match args {
        [flag, _path] if flag == "--output" => {
            eprintln!("Even package generation is intentionally unavailable: the .ehpk format, signed installation route, iOS HTTP/SSE permission model, and whitelist semantics have not yet been verified on a physical G2. Herden will not produce an unproven package.");
            Ok(1)
        }
        _ => {
            eprintln!("usage: herden glasses package --output ./herden-hud.ehpk");
            Ok(2)
        }
    }
}

fn usage_enable() -> io::Result<i32> {
    eprintln!("usage: herden glasses enable [--bind ADDRESS] [--port PORT] [--controls|--read-only] [--reconfigure]");
    Ok(2)
}

fn help() {
    eprintln!("herden glasses commands:");
    eprintln!("  herden glasses enable [--bind ADDRESS] [--port PORT] [--controls|--read-only]");
    eprintln!("  herden glasses status");
    eprintln!("  herden glasses disable");
    eprintln!("  herden glasses token show|rotate");
    eprintln!("  herden glasses package --output ./herden-hud.ehpk");
}
