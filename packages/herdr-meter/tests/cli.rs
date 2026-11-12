use std::process::Command;

#[test]
fn configuration_commands_are_not_exposed() {
    for command in ["setup", "doctor"] {
        let output = Command::new(env!("CARGO_BIN_EXE_hmeter"))
            .arg(command)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(2));
        let help = String::from_utf8(output.stderr).unwrap();
        assert!(help.contains("hmeter ingest"));
        assert!(!help.contains("hmeter setup"));
        assert!(!help.contains("hmeter doctor"));
    }
}
