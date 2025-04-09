use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use uuid::Uuid;

use crate::config::{
    BuildConfig, Builder, FlagVariantKind, ModuleConfiguration, OutputKind, Task,
    DEFAULT_BUILD_MANIFEST, DEFAULT_FLAGS_FILENAME,
};
use crate::errors::BuildError;
use crate::flag_generator::Flag;

/// Represents the build process of a task, including the initial configuration and produced output files and flags.
#[derive(serde::Serialize, Debug)]
pub struct TaskBuildContainer<'a> {
    out_dir: PathBuf,
    pub task: &'a Task,
    /// For batch mode, this is > 1, for a sequential build, this is 1
    pub outputs: Vec<IntermediateOutput>,
    batched: bool,
}
impl<'a> TaskBuildContainer<'a> {
    pub fn new(
        out_dir: PathBuf,
        task: &'a Task,
        outputs: Vec<IntermediateOutput>,
        batched: bool,
    ) -> Self {
        Self {
            out_dir,
            task,
            outputs,
            batched,
        }
    }
}

impl TaskBuildContainer<'_> {
    pub fn validate_output(&mut self) -> Result<(), BuildError> {
        let dir = self.out_dir.to_path_buf();
        let batched = self.batched;
        let task_id = self.task.id.clone();
        for intermediate in &mut self.outputs {
            for item in &mut intermediate.outputs {
                // batched builder has many uuids and cannot keep it in `out_dir` directly
                let path = if batched {
                    dir.join(intermediate.uuid.to_string()).join(&task_id)
                } else {
                    dir.join(item.kind.get_filename())
                };
                let path = match path.canonicalize() {
                    Ok(p) => p,
                    Err(e) => {
                        tracing::error!(
                             "Failed to canonicalize build output path for file {}: {}. Is builder using given output directory correctly or configuration has unintentional output files defined?",
                             &item.kind.get_filename().to_string_lossy(),
                             e
                         );
                        return Err(BuildError::OutputVerificationFailed(e.to_string()));
                    }
                };
                match fs::metadata(&path) {
                    Ok(_) => {
                        tracing::debug!("File exists: {}", path.display());
                        item.update_path(path);
                    }
                    Err(e) => {
                        tracing::error!("File does not exist: {}", path.display());
                        tracing::error!(
                            "The file was configured output with '{}' use case",
                            &item.kind.kind()
                        );
                        return Err(BuildError::OutputVerificationFailed(e.to_string()));
                    }
                }
            }
        }
        Ok(())
    }
}

// All flags in a single task's stages
#[derive(serde::Serialize, Clone, Debug)]
pub struct IntermediateOutput {
    pub uuid: Uuid,
    pub stage_flags: Vec<Flag>,
    pub outputs: Vec<OutputItem>,
}

impl IntermediateOutput {
    pub fn new(uuid: Uuid, stage_flags: Vec<Flag>, outputs: Vec<OutputItem>) -> Self {
        Self {
            uuid,
            stage_flags,
            outputs,
        }
    }
    pub fn validate_readme_count(&self) -> Result<(), BuildError> {
        let readme_count = self
            .outputs
            .iter()
            .filter(|output| matches!(output.kind, OutputKind::Readme(_)))
            .count();
        if readme_count != 1 {
            return Err(BuildError::OutputVerificationFailed(format!(
                "Expected exactly one readme file, found {}",
                readme_count
            )));
        }
        Ok(())
    }

    /// Files that should be delivered for the end-user
    pub fn get_resource_files(&self) -> Vec<OutputItem> {
        self.outputs
            .iter()
            .filter_map(|output| match output.kind {
                OutputKind::Resource(_) => Some(output.to_owned()),
                _ => None,
            })
            .collect()
    }
    /// Get readme.txt from the output files
    pub fn get_readme(&self) -> Option<&OutputItem> {
        self.outputs
            .iter()
            .find(|output| matches!(output.kind, OutputKind::Readme(_)))
    }
    /// Update common files that apply to all flag entries
    pub fn update_files(&mut self, items: Vec<OutputItem>) {
        for item in items {
            if let Some(index) = self.outputs.iter().position(|x| x.kind == item.kind) {
                self.outputs[index] = item;
            } else {
                self.outputs.push(item);
            }
        }
    }
}

/// Build process can return metadata about the task
#[derive(serde::Serialize, serde::Deserialize, Debug)]
struct Meta {
    pub task: String,
    pub challenges: Vec<Challenge>,
}

#[derive(serde::Serialize, serde::Deserialize, Debug)]
struct Challenge {
    pub uuid: Uuid,
    pub flag: String,
    pub url: Option<String>,
}

fn create_flags_by_task<'a>(
    task_config: &'a Task,
    module_config: &'a ModuleConfiguration,
    uuid: Uuid,
) -> Vec<Flag> {
    let mut flags = Vec::with_capacity(task_config.stages.len());
    for stage in &task_config.stages {
        // Get ID from stage or fall back to task ID
        let id = stage.id.as_deref().unwrap_or(&task_config.id);
        let flag = match stage.flag.kind {
            FlagVariantKind::UserDerived => Flag::new_user_flag(
                id.into(),
                &module_config.flag_config.user_derived.algorithm,
                &module_config.flag_config.user_derived.secret,
                id,
                &uuid,
            ),
            FlagVariantKind::PureRandom => {
                Flag::new_random_flag(id.into(), module_config.flag_config.pure_random.length)
            }
            FlagVariantKind::RngSeed => Flag::new_rng_seed(
                id.into(),
                &module_config.flag_config.user_derived.algorithm,
                &module_config.flag_config.user_derived.secret,
                id,
                &uuid,
            ),
        };
        flags.push(flag);
    }
    flags
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
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
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
    pub fn update_path(&mut self, path: PathBuf) {
        self.kind = self.kind.with_new_path(path);
    }
}

// Guarantee that the output directory exists
// The process's current working directory is set to be the build directory
// This means that output directory should relatively referenced based on the CWD of this program
fn verify_output_dir(
    output_directory: &Path,
    suffix: &str,
    task_id: &str,
) -> Result<PathBuf, BuildError> {
    let builder_output_dir = output_directory.join(suffix).join(task_id);
    // Create all required directories in the path
    match fs::create_dir_all(&builder_output_dir) {
        Ok(_) => Ok(builder_output_dir),
        Err(e) => {
            tracing::error!(
                "Failed to create the output directory for task {}: {}. Confirm the task build directory is correct.",
                task_id,
                e
            );
            Err(BuildError::InvalidOutputDirectory(e.to_string()))
        }
    }
}

fn run_subprocess(
    entrypoint: &str,
    build_manifest: &mut TaskBuildContainer,
) -> Result<(), BuildError> {
    let json_path = build_manifest.out_dir.join(DEFAULT_BUILD_MANIFEST);
    serde_json::to_writer_pretty(fs::File::create(&json_path).unwrap(), &build_manifest)
        .map_err(|e| BuildError::SerdeDerserializationFailed(e.to_string()))?;

    let build_envs = HashMap::from([(
        "BUILD_MANIFEST".to_string(),
        json_path.to_str().unwrap_or_default().to_string(),
    )]);

    let output = std::process::Command::new("sh")
        .arg(entrypoint)
        .env_clear()
        .envs(build_envs)
        .current_dir(&build_manifest.task.build.directory)
        .output();

    let output = match output {
        Ok(output) => output,
        Err(e) => {
            return Err(BuildError::ShellSubprocessError(format!(
                "The build process of task {} failed prematurely: {}",
                build_manifest.task.id, e
            )));
        }
    };
    if output.status.success() {
        build_manifest.validate_output()?;

        // If the task has a seed-based flag, we must capture the resulting flag from the process output
        // Stored into the file flags.json by default, using same key as the passed environment variable
        map_rng_seed_to_flag(
            &mut build_manifest.outputs,
            &build_manifest.out_dir,
            build_manifest.task,
        )?;

        Ok(())
    } else {
        Err(BuildError::ShellSubprocessError(format!(
            "The build process for task {} failed with non-zero exit code. Error: {}",
            build_manifest.task.id,
            std::str::from_utf8(&output.stderr).unwrap_or("Unable to read stderr")
        )))
    }
}

pub fn build_batch<'a>(
    module_config: &'a ModuleConfiguration,
    task_config: &'a Task,
    output_directory: &'a Path,
) -> Result<TaskBuildContainer<'a>, BuildError> {
    if !task_config.build.directory.exists() {
        return Err(BuildError::InvalidOutputDirectory(
            task_config.build.directory.display().to_string(),
        ));
    }

    // Extract batch count from stages if present - there should be some

    let batch_count = match task_config.batch {
        Some(ref config) => config.count,
        None => {
            tracing::error!("Batch count not found in task stages.");
            return Err(BuildError::StageHadNoBatch(format!(
                "the criminal was task {}",
                task_config.id
            )));
        }
    };
    // generate a UUID for each task based on batch count
    let uuids: Vec<Uuid> = (0..batch_count).map(|_| Uuid::now_v7()).collect();

    // let mut flags_of_flags = Vec::with_capacity(task_config.stages.len());
    let builder_output_dir = verify_output_dir(output_directory, "", "")?;
    //
    let mut entries = Vec::with_capacity(uuids.len());
    for uuid_value in uuids {
        let flags = create_flags_by_task(task_config, module_config, uuid_value);

        let expected_outputs: Vec<OutputItem> = task_config
            .build
            .output
            .iter()
            .map(|output| OutputItem::new(output.kind.clone()))
            .collect();
        let entry = IntermediateOutput {
            uuid: uuid_value,
            stage_flags: flags,
            outputs: expected_outputs,
        };

        entries.push(entry);
    }
    // PANICS: We are creating the file in the output directory, which is guaranteed to exist (unless someone removed it between check and this point)
    let mut build_manifest = TaskBuildContainer {
        out_dir: builder_output_dir,
        task: task_config,
        outputs: entries,
        batched: true,
    };

    match task_config.build.builder {
        Builder::Shell(ref entrypoint) => {
            run_subprocess(&entrypoint.entrypoint, &mut build_manifest)?
        }
        Builder::Nix(_) => todo!("Nix builder not implemented"),
    }
    // build_manifest.
    Ok(build_manifest)
}

fn map_rng_seed_to_flag(
    flags: &mut [IntermediateOutput],
    builder_output_dir: &Path,
    task_config: &Task,
) -> Result<(), BuildError> {
    // TODO batch mode not supported
    for flag in flags[0].stage_flags.iter_mut() {
        let flag_key = flag.get_flag_type_value_pair().0;
        if let Flag::RngSeed(ref mut rng_seed) = flag {
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
            let seeded_flags: HashMap<String, String> = serde_json::from_reader(reader)?;
            // Same key than passed for the build process
            if let Some(seed) = seeded_flags.get(&flag_key) {
                rng_seed.update_suffix(seed.to_owned());
            } else {
                return Err(BuildError::FlagCollectionError(format!(
                    "Seeded flag for task {} is not found from the output file",
                    task_config.id
                )));
            }
        }
    }
    Ok(())
}

/// Build that is supposed to repeat many times and generate different variations
pub fn build_sequential<'a>(
    module_config: &'a ModuleConfiguration,
    task_config: &'a Task,
    uuid: Uuid,
    output_directory: &Path,
    // If the build is repeated, tells the number, starting from 1
    _build_number: usize,
) -> Result<IntermediateOutput, BuildError> {
    let flags = create_flags_by_task(task_config, module_config, uuid);
    // Guarantee that the output directory exists
    let builder_output_dir =
        verify_output_dir(output_directory, &uuid.to_string(), &task_config.id)?;
    let expected_outputs: Vec<OutputItem> = task_config
        .build
        .output
        .iter()
        .map(|output| OutputItem::new(output.kind.clone()))
        .collect();
    let mut build_manifest = TaskBuildContainer {
        out_dir: builder_output_dir,
        task: task_config,
        outputs: vec![IntermediateOutput {
            uuid,
            stage_flags: flags,
            outputs: expected_outputs,
        }],
        batched: false,
    };
    match task_config.build.builder {
        Builder::Shell(ref entrypoint) => {
            tracing::debug!(
                "Running shell command: {} in directory: {}",
                entrypoint.entrypoint,
                &task_config.build.directory.display()
            );

            run_subprocess(&entrypoint.entrypoint, &mut build_manifest)?
        }
        Builder::Nix(_) => todo!("Nix builder not implemented"),
    }
    debug_assert!(
        build_manifest.outputs.len() == 1,
        "The sequential build should have only one output"
    );
    Ok(build_manifest.outputs.remove(0))
}
