use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn cli_simple_validate() -> Result<(), Box<dyn std::error::Error>> {
    Command::cargo_bin("cli")?
        .args([
            "--config",
            "tests/data/configs/simple_shell.toml",
            "validate",
        ])
        .assert()
        .stdout(predicate::str::contains("ModuleConfiguration"))
        .success();
    Ok(())
}
