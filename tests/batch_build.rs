// uses data/configs/batch_count.toml
use assert_cmd::Command;

#[test]
fn batch_simple_validate() -> Result<(), Box<dyn std::error::Error>> {
    let temp_dir = tempfile::tempdir()?;
    Command::cargo_bin("cli")?
        .args([
            "--config",
            "tests/data/configs/batch_count.toml",
            "generate",
            "--task",
            "task002",
            "--output-dir",
            temp_dir.path().to_str().unwrap(),
        ])
        .assert()
        .success();

    let entries: Vec<_> = std::fs::read_dir(temp_dir.path())?
        .filter_map(|entry| {
            entry.ok().and_then(|e| {
                if let Ok(file_type) = e.file_type() {
                    if file_type.is_dir() {
                        Some(e)
                    } else {
                        None
                    }
                } else {
                    None
                }
            })
        })
        .collect();

    println!("Entries: {:?}", entries);

    assert_eq!(entries.len(), 3, "Should have 5 directories");

    // test just one randomly
    let uid_dir = &entries[0];
    let task_dirs: Vec<_> = std::fs::read_dir(uid_dir.path())?.collect::<Result<_, _>>()?;
    let task_dir_path = task_dirs[0].path();

    // Check if required files exist
    let readme_path = task_dir_path.join("readme.txt");
    let encrypted = task_dir_path.join("encrypted_output.txt");
    let reversable = task_dir_path.join("reversable.bin");

    assert!(
        readme_path.exists(),
        "readme.txt should exist in the directory"
    );
    assert!(
        encrypted.exists(),
        "encrypted_output.txt should exist in the directory"
    );
    assert!(
        reversable.exists(),
        "reversable.bin should exist in the directory"
    );
    // std::fs::remove_dir_all(temp_dir.path())?;
    Ok(())
}
