use std::collections::HashMap;
use std::fs;
use std::path::Path;
use uuid::Uuid;

use crate::config::{BuildConfig, Builder, ModuleConfiguration, OutputKind, Task};
use crate::flag_generator::Flag;

const OUTPUT_DIRECTORY: &str = "output/";

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
        match stage.flag.kind.as_str() {
            "user_derived" => {
                let flag = Flag::new_user_flag(
                    id.into(),
                    &module_config.flag_types.user_derived.algorithm,
                    &module_config.flag_types.user_derived.secret,
                    id,
                    &uuid,
                );
                let (flag_key, flag_value) = flag.get_flag_type_value_pair();
                flags_pairs.insert(flag_key, flag_value);
                flags.push(flag);
            }
            "pure_random" => {
                let flag =
                    Flag::new_random_flag(id.into(), module_config.flag_types.pure_random.length);
                let (flag_key, flag_value) = flag.get_flag_type_value_pair();
                flags_pairs.insert(flag_key, flag_value);
                flags.push(flag);
            }
            "rng_seed" => {
                let flag = Flag::new_user_seed_flag(
                    id.into(),
                    &module_config.flag_types.user_derived.algorithm,
                    &module_config.flag_types.user_derived.secret,
                    id,
                    &uuid,
                );
                let (flag_key, flag_value) = flag.get_flag_type_value_pair();
                flags_pairs.insert(flag_key, flag_value);
                flags.push(flag);
            }
            _ => panic!("Invalid flag type"),
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
    pub fn get_readme(&self) -> Option<&OutputItem> {
        self.files
            .iter()
            .find(|output| matches!(output.kind, OutputKind::Readme(_)))
    }

    pub fn refresh_files(&mut self, items: Vec<OutputItem>) {
        for item in items {
            if let Some(index) = self.files.iter().position(|x| x.kind == item.kind) {
                self.files[index] = item;
            } else {
                self.files.push(item);
            }
        }
    }
}

pub fn build_task(
    module_config: &ModuleConfiguration,
    task_config: &Task,
    uuid: Uuid,
) -> Result<TaskBuildProcessOutput, Box<dyn std::error::Error>> {
    let (flags, mut build_envs) = create_flag_id_pairs_by_task(task_config, module_config, uuid);

    match task_config.build.builder {
        Builder::Shell(ref entrypoint) => {
            let build_output = Path::new(OUTPUT_DIRECTORY).join(uuid.to_string());
            let builder_relative_dir = Path::new(&task_config.build.directory).join(&build_output);
            tracing::debug!(
                "Running shell command: {} with flags: {:?} in directory: {}",
                entrypoint.entrypoint,
                build_envs,
                &builder_relative_dir.display()
            );
            // Create all required directories in the path
            match fs::create_dir_all(&builder_relative_dir) {
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
            build_envs.insert(
                "OUTPUT_DIR".to_string(),
                build_output.to_str().unwrap_or_default().to_string(),
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
                    tracing::error!(
                        "The build process of task {} failed prematurely: {}",
                        task_config.id,
                        e
                    );
                    std::process::exit(1);
                }
            };
            let mut outputs = Vec::with_capacity(task_config.build.output.len());
            if output.status.success() {
                for output in &task_config.build.output {
                    let path = builder_relative_dir
                        .join(output.kind.get_filename())
                        .canonicalize()?;
                    match fs::metadata(&path) {
                        Ok(_) => {
                            tracing::debug!("File exists: {}", path.display());
                            outputs.push(OutputItem::new(output.kind.with_new_path(path)));
                        }

                        Err(_) => {
                            tracing::error!("File does not exist: {}", path.display());
                            tracing::error!(
                                "The file was configured output with '{}' use case",
                                output.kind.kind()
                            );
                            std::process::exit(1);
                        }
                    }
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
