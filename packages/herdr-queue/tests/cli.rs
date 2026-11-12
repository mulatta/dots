use std::process::Command;

#[test]
fn configuration_commands_are_not_exposed() {
    for command in ["setup", "doctor"] {
        let output = Command::new(env!("CARGO_BIN_EXE_hq"))
            .arg(command)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(2));
        let help = String::from_utf8(output.stderr).unwrap();
        assert!(help.contains("hq ingest"));
        assert!(!help.contains("hq setup"));
        assert!(!help.contains("hq doctor"));
    }
}
