use assert_cmd::Command;

#[test]
fn cli_simple_validate() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempfile::tempdir()?;
    Command::cargo_bin("cli")?
        .args([
            "--config",
            "tests/data/configs/simple_shell.toml",
            "generate",
            "--output-dir",
            temp_dir.path().to_str().unwrap(),
            "--task",
            "task001",
            "-n",
            "5",
        ])
        .env("RUST_LOG", "debug")
        .assert()
        .success();
    // Check that tempdir has 5 dirs and validate content of the first dir
    let entries: Vec<_> = std::fs::read_dir(temp_dir.path())?.collect::<Result<_, _>>()?;
    assert_eq!(entries.len(), 5, "Should have 5 directories");

    let uid_dir = &entries[0];
    let task_dirs: Vec<_> = std::fs::read_dir(uid_dir.path())?.collect::<Result<_, _>>()?;
    let task_dir_path = task_dirs[0].path();

    // Check if required files exist
    let readme_path = task_dir_path.join("readme.txt");
    let secret_path = task_dir_path.join("secret.sh");

    assert!(
        readme_path.exists(),
        "readme.txt should exist in the directory"
    );
    assert!(
        secret_path.exists(),
        "secret.sh should exist in the directory"
    );
    std::fs::remove_dir_all(temp_dir.path())?;
    Ok(())
}
