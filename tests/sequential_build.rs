use assert_cmd::Command;
use predicates::prelude::*;

const SIMPLE_SHELL_ARGS: &[&str] = &[
    "--config",
    "tests/data/configs/simple_shell.toml",
    "generate",
    "--output-dir",
    // Placeholder – at least output dir must be set dynamically
    "--task",
    "task001",
    "-n",
    "3",
];

#[test]
fn cli_simple_sequentical_validate() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempfile::tempdir()?;
    let mut args = SIMPLE_SHELL_ARGS.to_vec();
    args.insert(4, temp_dir.path().to_str().unwrap());

    Command::cargo_bin("cli")?
        .args(args)
        .env("RUST_LOG", "info")
        .assert()
        .success();

    // Check that tempdir has 5 dirs and validate content of the first dir
    let entries: Vec<_> = std::fs::read_dir(temp_dir.path())?.collect::<Result<_, _>>()?;
    assert_eq!(entries.len(), 3, "Should have 5 directories");

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

#[test]
fn cli_simple_shell_with_moodle() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempfile::tempdir()?;
    let mut args = SIMPLE_SHELL_ARGS.to_vec();
    args.insert(4, temp_dir.path().to_str().unwrap());
    args.push("moodle");
    args.push("--disable-upload");
    args.push("--category");
    args.push("test_category");
    args.push("--output");
    let path = temp_dir.path().join("moodle.xml");
    args.push(path.to_str().unwrap());

    Command::cargo_bin("cli")?
        .args(args)
        .env("RUST_LOG", "info")
        .assert()
        .success();
    // check if quiz.xml exists in the output dir
    if !temp_dir.path().join("moodle.xml").exists() {
        panic!("moodle.xml should exist in the directory");
    }
    // check if test_category in the xml with predicates
    let contents = std::fs::read_to_string(temp_dir.path().join("moodle.xml"))?;
    let predicate = predicate::str::contains("test_category");
    let union = predicate.and(predicate::str::contains("task001"));
    assert!(union.eval(&contents));
    Ok(())
}
