use std::collections::HashMap;
use std::fs;
use std::path::Path;
use uuid::Uuid;

use crate::config::{
    BuildConfig, Builder, FlagVariantKind, ModuleConfiguration, OutputKind, Task,
    DEFAULT_FLAGS_FILENAME,
};
use crate::errors::BuildError;
use crate::flag_generator::Flag;

fn create_flag_id_pairs_by_task<'a>(
    task_config: &'a Task,
    module_config: &'a ModuleConfiguration,
    uuid: Uuid,
) -> (Vec<Flag>, HashMap<String, String>) {
    let mut flags_pairs = HashMap::with_capacity(task_config.stages.len());
    let mut flags = Vec::with_capacity(task_config.stages.len());
    for stage in &task_config.stages {
        // let task_id = part.id.clone();
        let id: &str;
        if let Some(stage_id) = &stage.id {
            id = stage_id;
        } else {
            id = &task_config.id
        }
        match stage.flag.kind {
            FlagVariantKind::UserDerived => {
                let flag = Flag::new_user_flag(
                    id.into(),
                    &module_config.flag_config.user_derived.algorithm,
                    &module_config.flag_config.user_derived.secret,
                    id,
                    &uuid,
                );
                let (flag_key, flag_value) = flag.get_flag_type_value_pair();
                flags_pairs.insert(flag_key, flag_value);
                flags.push(flag);
            }
            FlagVariantKind::PureRandom => {
                let flag =
                    Flag::new_random_flag(id.into(), module_config.flag_config.pure_random.length);
                let (flag_key, flag_value) = flag.get_flag_type_value_pair();
                flags_pairs.insert(flag_key, flag_value);
                flags.push(flag);
            }
            FlagVariantKind::RngSeed => {
                let flag = Flag::new_user_seed_flag(
                    id.into(),
                    &module_config.flag_config.user_derived.algorithm,
                    &module_config.flag_config.user_derived.secret,
                    id,
                    &uuid,
                );
                let (flag_key, flag_value) = flag.get_flag_type_value_pair();
                flags_pairs.insert(flag_key, flag_value);
                flags.push(flag);
            }
        };
    }
    (flags, flags_pairs)
}

#[allow(dead_code)]
fn get_build_info(
    module_config: &mut ModuleConfiguration,
    task_id: String,
) -> Result<&BuildConfig, String> {
    for category in &mut module_config.categories {
        for task in &category.tasks {
            if task_id == task.id {
                return Ok(task.build.as_ref());
            }
        }
    }
    Err(format!(
        "Build information for task with id {} not found!",
        task_id
    ))
}
/// Couple output items together, so we link points to the correct output
#[derive(Debug, Clone)]
pub struct OutputItem {
    pub kind: OutputKind,
    pub link: Option<String>,
}

impl OutputItem {
    pub fn new(kind: OutputKind) -> Self {
        Self { kind, link: None }
    }
    pub fn set_link(&mut self, link: String) {
        self.link = Some(link);
    }
}

/// Meta object that should include everything from the build process
/// Single task can have multiple subtasks, which requires embedding multiple flags at once
#[derive(Debug)]
pub struct TaskBuildProcessOutput {
    pub uiid: Uuid,
    pub task_id: String,
    pub flags: Vec<Flag>,
    pub files: Vec<OutputItem>,
}
impl TaskBuildProcessOutput {
    pub fn new(uuid: Uuid, task_id: String, flags: Vec<Flag>, files: Vec<OutputItem>) -> Self {
        // The task can have only one file related to instructions
        let readme_count = files
            .iter()
            .filter(|output| matches!(output.kind, OutputKind::Readme(_)))
            .count();
        if readme_count != 1 {
            tracing::error!(
                "The build process output must have exactly one readme file, found {}.",
                readme_count
            );
            std::process::exit(1);
        }
        Self {
            uiid: uuid,
            task_id,
            flags,
            files,
        }
    }
    /// Files that should be delivered for the end-user
    pub fn get_resource_files(&self) -> Vec<OutputItem> {
        self.files
            .iter()
            .filter_map(|output| match output.kind {
                OutputKind::Resource(_) => Some(output.to_owned()),
                _ => None,
            })
            .collect()
    }
    /// Get readme.txt from the output files
    pub fn get_readme(&self) -> Option<&OutputItem> {
        self.files
            .iter()
            .find(|output| matches!(output.kind, OutputKind::Readme(_)))
    }

    pub fn update_files(&mut self, items: Vec<OutputItem>) {
        for item in items {
            if let Some(index) = self.files.iter().position(|x| x.kind == item.kind) {
                self.files[index] = item;
            } else {
                self.files.push(item);
            }
        }
    }
}
/// Verify the build output files and generates absolute paths
fn verify_build_files(
    task_config: &Task,
    builder_output_dir: &Path,
) -> Result<Vec<OutputItem>, BuildError> {
    let mut outputs = Vec::with_capacity(task_config.build.output.len());

    for output in &task_config.build.output {
        tracing::debug!(
            "Verifying build output file '{}' and joining it with '{}'",
            output.kind.get_filename().to_string_lossy(),
            builder_output_dir.display()
        );
        let path = match builder_output_dir
            .join(output.kind.get_filename())
            .canonicalize()
        {
            Ok(p) => {
                tracing::debug!("Output filepath valid: {}", p.display());
                p
            }
            Err(e) => {
                tracing::error!(
                    "Failed to canonicalize build output path for file {}: {}. Is builder using given output directory correctly or configuration has unintentional output files defined?",
                    &output.kind.get_filename().to_string_lossy(),
                    e
                );
                return Err(BuildError::OutputVerificationFailed(e.to_string()));
            }
        };
        match fs::metadata(&path) {
            Ok(_) => {
                tracing::debug!("File exists: {}", path.display());
                outputs.push(OutputItem::new(output.kind.with_new_path(path)));
            }

            Err(e) => {
                tracing::error!("File does not exist: {}", path.display());
                tracing::error!(
                    "The file was configured output with '{}' use case",
                    output.kind.kind()
                );
                return Err(BuildError::OutputVerificationFailed(e.to_string()));
            }
        }
    }
    Ok(outputs)
}

pub fn build_task(
    module_config: &ModuleConfiguration,
    task_config: &Task,
    uuid: Uuid,
    output_directory: &Path,
    // If the build is repeated, tells the number, starting from 1
    build_number: usize,
) -> Result<TaskBuildProcessOutput, BuildError> {
    let (mut flags, mut build_envs) =
        create_flag_id_pairs_by_task(task_config, module_config, uuid);

    match task_config.build.builder {
        Builder::Shell(ref entrypoint) => {
            let builder_output_dir = output_directory
                .join(uuid.to_string())
                .join(&task_config.id);
            // Create all required directories in the path
            match fs::create_dir_all(&builder_output_dir) {
                Ok(_) => (),
                Err(e) => {
                    tracing::error!(
                        "Failed to create the output directory for task {}: {}. Confirm the task build directory is correct.",
                        task_config.id,
                        e
                    );
                    std::process::exit(1);
                }
            }
            // The process's current working directory is set to be the build directory
            // This means that output directory should relatively referenced based on the CWD of this program
            build_envs.extend([
                (
                    "OUTPUT_DIR".to_string(),
                    builder_output_dir.to_str().unwrap_or_default().to_string(),
                ),
                ("BUILD_NUMBER".to_string(), build_number.to_string()),
            ]);
            tracing::debug!(
                "Running shell command: {} with flags: {:?} in directory: {}",
                entrypoint.entrypoint,
                build_envs,
                &task_config.build.directory.display()
            );

            let output = std::process::Command::new("sh")
                .arg(&entrypoint.entrypoint)
                .env_clear()
                .envs(&build_envs)
                .current_dir(&task_config.build.directory)
                .output();

            let output = match output {
                Ok(output) => output,
                Err(e) => {
                    return Err(BuildError::ShellSubprocessError(format!(
                        "The build process of task {} failed prematurely: {}",
                        task_config.id, e
                    )));
                }
            };
            if output.status.success() {
                let outputs = verify_build_files(task_config, &builder_output_dir)?;
                // If the task has a seed-based flag, we must capture the resulting flag from the process output
                // Stored into the file seeded_flags.json, using same key as the passed environment variable
                for flag in flags.iter_mut() {
                    let flag_key = flag.get_flag_type_value_pair().0;
                    if let Flag::UserSeedFlag(ref mut user_seed_flag) = flag {
                        let path = task_config
                            .build
                            .output
                            .iter()
                            .find_map(|output| {
                                if let OutputKind::Flags(ref pathbuf) = output.kind {
                                    Some(builder_output_dir.join(pathbuf))
                                } else {
                                    None
                                }
                            })
                            .unwrap_or_else(|| builder_output_dir.join(DEFAULT_FLAGS_FILENAME));
                        let file = match fs::File::open(&path) {
                            Ok(file) => file,
                            Err(e) => {
                                tracing::error!(
                                    "Failed to open flags.json for task {}: {}",
                                    task_config.id,
                                    e
                                );
                                std::process::exit(1);
                            }
                        };
                        let reader = std::io::BufReader::new(file);
                        let seeded_flags: HashMap<String, String> =
                            serde_json::from_reader(reader)?;
                        // Same key than passed for the build process
                        if let Some(seed) = seeded_flags.get(&flag_key) {
                            user_seed_flag.update_suffix(seed.to_owned());
                        } else {
                            tracing::error!(
                                "Seed flag for task {} not found in the output file",
                                task_config.id
                            );
                            std::process::exit(1);
                        }
                    }
                }
                for flag in &flags {
                    tracing::debug!("Flag: {:?}", flag);
                }
                Ok(TaskBuildProcessOutput::new(
                    uuid,
                    task_config.id.to_owned(),
                    flags,
                    outputs,
                ))
            } else {
                tracing::error!(
                    "The build process for task {} ended with non-zero exit code: {}",
                    task_config.id,
                    std::str::from_utf8(&output.stderr).unwrap()
                );
                std::process::exit(1);
            }
        }
        Builder::Nix(_) => todo!("Nix builder not implemented"),
    }
}
