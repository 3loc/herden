//! Native editor settings for Agents launched by Herden. These are scoped to
//! the launched process; unrelated agent configuration and shell editing mode
//! are preserved. User-supplied launch arguments can override the defaults.

use crate::detect::Agent;

pub(crate) fn launch_options(agent: Agent) -> &'static [&'static str] {
    match agent {
        Agent::Claude => &["--settings", r#"{"editorMode":"vim"}"#],
        Agent::Codex => &["-c", "tui.vim_mode_default=true"],
        _ => &[],
    }
}

pub(crate) fn apply_to_resume(argv: &mut Vec<String>) {
    let Some(kind) = argv
        .first()
        .and_then(|name| crate::detect::parse_agent_label(name))
    else {
        return;
    };
    argv.splice(
        1..1,
        launch_options(kind).iter().map(|arg| (*arg).to_string()),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_vi_options_do_not_change_permission_or_model_settings() {
        let claude = launch_options(Agent::Claude);
        assert_eq!(claude[0], "--settings");
        let settings: serde_json::Value = serde_json::from_str(claude[1]).unwrap();
        assert_eq!(settings, serde_json::json!({"editorMode": "vim"}));
        assert_eq!(
            launch_options(Agent::Codex),
            &["-c", "tui.vim_mode_default=true"]
        );
    }

    #[test]
    fn resume_keeps_subcommand_and_session_identity() {
        let mut argv = vec!["codex".into(), "resume".into(), "session-123".into()];
        apply_to_resume(&mut argv);
        assert_eq!(
            argv,
            [
                "codex",
                "-c",
                "tui.vim_mode_default=true",
                "resume",
                "session-123"
            ]
        );
        let mut argv = vec!["claude".into(), "--resume".into(), "session-456".into()];
        apply_to_resume(&mut argv);
        assert_eq!(&argv[3..], &["--resume", "session-456"]);
    }

    #[test]
    fn other_agents_are_unchanged() {
        let mut argv = vec!["pi".into(), "--session".into(), "/tmp/session.jsonl".into()];
        let original = argv.clone();
        apply_to_resume(&mut argv);
        assert_eq!(argv, original);
    }
}
