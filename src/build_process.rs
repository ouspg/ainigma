use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
// use tracing::instrument;
use uuid::Uuid;

use crate::config::{
    BuildConfig, Builder, DEFAULT_BUILD_MANIFEST, DEFAULT_FLAGS_FILENAME, FlagVariantKind,
    ModuleConfiguration, OutputKind, Task,
};
use crate::errors::BuildError;
use crate::flag_generator::Flag;

/// Represents the build process of a task, including the initial configuration and produced output files and flags.
#[derive(serde::Serialize, Debug)]
pub struct TaskBuildContainer<'a> {
    pub basedir: PathBuf,
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
            basedir: out_dir,
            task,
            outputs,
            batched,
        }
    }
}

impl TaskBuildContainer<'_> {
    pub fn validate_output(&mut self) -> Result<(), BuildError> {
        for intermediate in &mut self.outputs {
            for item in &mut intermediate.outputs {
                // The task instance directory should be defined already
                let pre_cano = &intermediate
                    .task_instance_dir
                    .join(item.kind.get_filename());
                let path = match pre_cano.canonicalize() {
                    Ok(p) => p,
                    Err(e) => {
                        tracing::error!("Failure in file '{}", &pre_cano.display(),);
                        tracing::error!(
                            "Failed to verify that build output path for file `{}` exist : {}. Is builder using given output directory correctly or configuration has unintentional output files defined?",
                            &item.kind.get_filename().to_string_lossy(),
                            e
                        );
                        return Err(BuildError::OutputVerificationFailed(e.to_string()));
                    }
                };
                item.update_path(path);
            }
        }
        Ok(())
    }
    /// Check if the task has any files to distribute other than the readme.txt. Defined by the existence of `OutputKind::Resource`.
    pub fn has_files_to_distribute(&self) -> bool {
        self.outputs
            .iter()
            .any(|intermediate| !intermediate.get_resource_files().is_empty())
    }
}

// All flags in a single task's stages
#[derive(serde::Serialize, Clone, Debug)]
pub struct IntermediateOutput {
    pub uuid: Uuid,
    pub stage_flags: Vec<Flag>,
    pub task_instance_dir: PathBuf,
    pub outputs: Vec<OutputItem>,
}

impl IntermediateOutput {
    pub fn new(
        uuid: Uuid,
        stage_flags: Vec<Flag>,
        task_instance_dir: PathBuf,
        outputs: Vec<OutputItem>,
    ) -> Self {
        Self {
            uuid,
            stage_flags,
            task_instance_dir,
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
    program: &str,
    args: Vec<&str>,
    build_manifest: &mut TaskBuildContainer,
    build_envs: HashMap<String, String>,
) -> Result<(), BuildError> {
    tracing::debug!("Running subprocess: {} with args: {:?}", program, args);

    let output = std::process::Command::new(program)
        .args(args)
        .envs(build_envs) // Use merged environment instead of env_clear()
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
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            tracing::info!("{}", line);
        }
        build_manifest.validate_output()?;

        // If the task has a seed-based flag, we must capture the resulting flag from the process output
        // Stored into the file flags.json by default, using same key as the passed environment variable
        map_rng_seed_to_flag(
            &mut build_manifest.outputs,
            &build_manifest.basedir,
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
    validate: bool,
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

        // Create UUID-specific directory for this batch
        let task_instance_dir =
            verify_output_dir(output_directory, &uuid_value.to_string(), &task_config.id)?;

        let entry = IntermediateOutput {
            uuid: uuid_value,
            stage_flags: flags,
            task_instance_dir,
            outputs: expected_outputs,
        };

        entries.push(entry);
    }
    // PANICS: We are creating the file in the output directory, which is guaranteed to exist (unless someone removed it between check and this point)
    let mut build_manifest = TaskBuildContainer {
        basedir: builder_output_dir,
        task: task_config,
        outputs: entries,
        batched: true,
    };

    let json_path = output_directory.join(DEFAULT_BUILD_MANIFEST);
    serde_json::to_writer_pretty(fs::File::create(&json_path).unwrap(), &build_manifest)
        .map_err(|e| BuildError::SerdeDerserializationFailed(e.to_string()))?;
    if validate {
        return Ok(build_manifest);
    }

    let mut build_envs = HashMap::from([(
        "BUILD_MANIFEST".to_string(),
        json_path.to_str().unwrap_or_default().to_string(),
    )]);
    let (program, program_args) = match task_config.build.builder {
        Builder::Shell(ref entrypoint) => ("sh", vec![entrypoint.entrypoint.as_str()]),
        Builder::Nix(ref entrypoint) => {
            // For nix to work, we need to set the environment variables
            let mut preserved_env = HashMap::new();
            let env_vars_to_preserve = [
                "PATH",
                "NIX_PATH",
                "NIX_PROFILES",
                "NIX_SSL_CERT_FILE",
                "NIX_STORE",
                "NIX_REMOTE",
                "NIX_USER_PROFILE_DIR",
            ];

            for var in &env_vars_to_preserve {
                if let Ok(value) = std::env::var(var) {
                    preserved_env.insert(var.to_string(), value);
                }
            }
            let final_env = preserved_env;
            build_envs.extend(final_env);

            ("nix", vec!["run", ".", &entrypoint.entrypoint])
        }
    };

    run_subprocess(program, program_args, &mut build_manifest, build_envs)?;

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
        if let Flag::RngSeed(rng_seed) = flag {
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
    validate: bool,
) -> Result<IntermediateOutput, BuildError> {
    let flags = create_flags_by_task(task_config, module_config, uuid);
    // Create the base output directory
    if !output_directory.exists() {
        fs::create_dir_all(output_directory).map_err(|e| {
            BuildError::InvalidOutputDirectory(format!(
                "Failed to create the base output directory: {}",
                e
            ))
        })?;
    }

    // Guarantee that the output directory exists with UUID/task_id structure
    let task_instance_dir =
        verify_output_dir(output_directory, &uuid.to_string(), &task_config.id)?;

    let expected_outputs: Vec<OutputItem> = task_config
        .build
        .output
        .iter()
        .map(|output| OutputItem::new(output.kind.clone()))
        .collect();
    let intermediate = IntermediateOutput::new(uuid, flags, task_instance_dir, expected_outputs);

    let json_path = if validate {
        // No race condition if we are validating
        output_directory.join(DEFAULT_BUILD_MANIFEST)
    } else {
        // For sequential builds we must use the task instance directory to avoid race condition
        intermediate.task_instance_dir.join(DEFAULT_BUILD_MANIFEST)
    };
    let mut build_manifest = TaskBuildContainer {
        basedir: output_directory.to_path_buf(),
        task: task_config,
        outputs: vec![intermediate],
        batched: false,
    };
    serde_json::to_writer_pretty(fs::File::create(&json_path).unwrap(), &build_manifest)
        .map_err(|e| BuildError::SerdeDerserializationFailed(e.to_string()))?;

    // We are just validating configuration and build-manifest.json
    if validate {
        return Ok(build_manifest.outputs[0].clone());
    }

    let build_envs = HashMap::from([(
        "BUILD_MANIFEST".to_string(),
        json_path.to_str().unwrap_or_default().to_string(),
    )]);

    match task_config.build.builder {
        Builder::Shell(ref entrypoint) => {
            tracing::debug!(
                "Running shell command: {} in directory: {}",
                entrypoint.entrypoint,
                &task_config.build.directory.display()
            );

            run_subprocess(
                "sh",
                vec![&entrypoint.entrypoint],
                &mut build_manifest,
                build_envs,
            )?
        }
        Builder::Nix(_) => todo!("Nix builder not implemented"),
    }
    debug_assert!(
        build_manifest.outputs.len() == 1,
        "The sequential build should have only one output"
    );
    Ok(build_manifest.outputs.remove(0))
}
