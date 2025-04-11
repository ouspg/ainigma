use crate::errors::ConfigError;
use crate::flag_generator;
use rand::rngs::StdRng;
use rand::{RngCore, SeedableRng};
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::HashSet;
use std::ffi::OsStr;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use uuid::Uuid;

const DEFAULT_NIX_FILENAME: &str = "flake.nix";
const DEFAULT_SH_FILENAME: &str = "entrypoint.sh";

const DEFAULT_BUILD_TIMEOUT: u32 = 300;
const DEFAULT_FILE_EXPIRATION: u32 = 31;
const DEFAULT_LINK_EXPIRATION: u32 = 7;
const DEFAULT_RANDOM_FLAG_LENGTH: u8 = 32;

pub(crate) const DEFAULT_FLAGS_FILENAME: &str = "flags.json";
pub(crate) const DEFAULT_BUILD_MANIFEST: &str = "build-manifest.json";

fn random_hex_secret() -> String {
    let mut random_bytes = vec![0u8; 32];
    let mut rng = StdRng::from_os_rng();
    rng.fill_bytes(random_bytes.as_mut_slice());
    random_bytes.iter().fold(
        String::with_capacity(random_bytes.len() * 2),
        |mut acc, b| {
            use std::fmt::Write;
            let _ = write!(acc, "{:02x}", b);
            acc
        },
    )
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ModuleConfiguration {
    pub identifier: Uuid,
    pub name: String,
    #[serde(default)]
    pub description: String,
    pub version: String,
    pub categories: Vec<Category>,
    #[serde(default)]
    pub flag_config: FlagConfig,
    #[serde(default)]
    pub deployment: Deployment,
}

impl ModuleConfiguration {
    pub fn new(
        identifier: Uuid,
        name: String,
        description: String,
        version: String,
        categories: Vec<Category>,
        flag_config: FlagConfig,
        deployment: Deployment,
    ) -> ModuleConfiguration {
        ModuleConfiguration {
            identifier,
            name,
            description,
            version,
            categories,
            flag_config,
            deployment,
        }
    }
    pub fn get_task_by_id(&self, id: &str) -> Option<&Task> {
        for category in &self.categories {
            for task in &category.tasks {
                if task.id == id {
                    return Some(task);
                }
            }
        }
        None
    }
    pub fn get_category_number_by_task_id(&self, id: &str) -> Option<u8> {
        for category in &self.categories {
            for task in &category.tasks {
                if task.id == id {
                    return Some(category.number);
                }
            }
        }
        None
    }
    pub fn get_category_by_task_id(&self, id: &str) -> Option<&Category> {
        for category in &self.categories {
            for task in &category.tasks {
                if task.id == id {
                    return Some(category);
                }
            }
        }
        None
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Category {
    pub tasks: Vec<Task>,
    pub number: u8,
    pub name: String,
}

impl Category {
    pub fn new(tasks: Vec<Task>, number: u8, name: String) -> Category {
        Category {
            tasks,
            number,
            name,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Task {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    pub points: f32,
    pub stages: Vec<TaskElement>,
    pub build: BuildConfig,
    pub batch: Option<BatchConfig>,
}

impl Task {
    pub fn new(
        id: String,
        name: String,
        description: String,
        points: f32,
        stages: Vec<TaskElement>,
        build: BuildConfig,
        batch: Option<BatchConfig>,
    ) -> Task {
        Task {
            id,
            name,
            description,
            points,
            stages,
            build,
            batch,
        }
    }
    /// Gets all task IDs for a task, including possible subtasks in `stages`
    /// Mainly used for validating that they are unique
    pub fn get_task_ids(&self) -> Vec<&str> {
        if self.stages.len() == 1 {
            vec![self.id.as_str()]
        } else {
            let mut task_ids = Vec::with_capacity(self.stages.len());
            for stage in &self.stages {
                if let Some(stage) = stage.id.as_ref() {
                    task_ids.push(stage.as_str());
                } else {
                    panic!("Unexpected empty stage ID");
                }
            }
            task_ids.sort();
            task_ids
        }
    }
}
#[derive(Debug, Serialize, Deserialize, Clone)]
#[non_exhaustive]
pub struct BatchConfig {
    pub count: usize,
}

#[derive(Debug, Serialize, Clone, PartialEq, Eq)]
#[non_exhaustive]
pub struct FlagVariant {
    pub kind: FlagVariantKind,
}

#[derive(Debug, Serialize, Clone, PartialEq, Eq)]
#[non_exhaustive]
pub enum FlagVariantKind {
    UserDerived,
    PureRandom,
    RngSeed,
}

impl FlagVariant {
    pub fn as_str(&self) -> &'static str {
        match self.kind {
            FlagVariantKind::UserDerived => "user_derived",
            FlagVariantKind::PureRandom => "pure_random",
            FlagVariantKind::RngSeed => "rng_seed",
        }
    }
}

impl std::fmt::Display for FlagVariant {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

impl FromStr for FlagVariant {
    type Err = ConfigError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "user_derived" => Ok(FlagVariant {
                kind: FlagVariantKind::UserDerived,
            }),
            "pure_random" => Ok(FlagVariant {
                kind: FlagVariantKind::PureRandom,
            }),
            "rng_seed" => Ok(FlagVariant {
                kind: FlagVariantKind::RngSeed,
            }),
            _ => Err(ConfigError::FlagTypeError),
        }
    }
}

impl<'de> Deserialize<'de> for FlagVariant {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct Helper {
            kind: String,
        }

        let helper = Helper::deserialize(deserializer)?;
        Self::from_str(&helper.kind).map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TaskElement {
    pub id: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    pub weight: Option<u8>,
    pub flag: FlagVariant,
}

impl TaskElement {
    pub fn new(
        id: Option<String>,
        name: Option<String>,
        description: Option<String>,
        weight: Option<u8>,
        flag: FlagVariant,
    ) -> TaskElement {
        TaskElement {
            id,
            name,
            description,
            weight,
            flag,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum BuildMode {
    Sequential,
    Batch,
}
impl BuildMode {
    pub fn all() -> &'static [BuildMode] {
        &[BuildMode::Sequential, BuildMode::Batch]
    }
}
impl core::fmt::Display for BuildMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BuildMode::Sequential => write!(f, "sequential"),
            BuildMode::Batch => write!(f, "batch"),
        }
    }
}

impl std::str::FromStr for BuildMode {
    type Err = ConfigError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "sequential" => Ok(BuildMode::Sequential),
            "batch" => Ok(BuildMode::Batch),
            _ => Err(ConfigError::BuildModeError(
                s.to_owned(),
                BuildMode::all()
                    .iter()
                    .map(|f| format!("{f}"))
                    .collect::<Vec<_>>()
                    .join(", "),
            )),
        }
    }
}

impl<'de> Deserialize<'de> for BuildMode {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Self::from_str(&s).map_err(serde::de::Error::custom)
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NonEmptyBuildModes(Vec<BuildMode>);
impl NonEmptyBuildModes {
    pub fn new(modes: Vec<BuildMode>) -> Result<Self, String> {
        if modes.is_empty() {
            Err("At least one BuildMode must be specified".to_string())
        } else {
            Ok(NonEmptyBuildModes(modes))
        }
    }
    pub fn contains(&self, mode: &BuildMode) -> bool {
        self.0.contains(mode)
    }
}
fn deserialize_non_empty_build_modes<'de, D>(
    deserializer: D,
) -> Result<NonEmptyBuildModes, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let modes = Vec::<BuildMode>::deserialize(deserializer)?;
    NonEmptyBuildModes::new(modes)
        .map_err(|err| serde::de::Error::custom(format!("Error in 'enabled_modes' field: {}", err)))
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct BuildConfig {
    pub directory: std::path::PathBuf,
    pub builder: Builder,
    pub output: Vec<BuildOutputFile>,
    // Note: all modes are disabled by default - task must explicitly enable one!
    #[serde(deserialize_with = "deserialize_non_empty_build_modes")]
    pub enabled_modes: NonEmptyBuildModes,
}
impl AsRef<BuildConfig> for BuildConfig {
    fn as_ref(&self) -> &BuildConfig {
        self
    }
}

impl BuildConfig {
    pub fn new(
        directory: std::path::PathBuf,
        builder: Builder,
        output: Vec<BuildOutputFile>,
        enabled_modes: NonEmptyBuildModes,
    ) -> BuildConfig {
        BuildConfig {
            directory,
            builder,
            output,
            enabled_modes,
        }
    }
    pub fn is_feature_enabled(&self, feature: BuildMode) -> bool {
        self.enabled_modes.contains(&feature)
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct BuildOutputFile {
    pub kind: OutputKind,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OutputKind {
    Internal(PathBuf),
    Resource(PathBuf),
    Readme(PathBuf),
    Meta(PathBuf),
    Flags(PathBuf),
}

impl OutputKind {
    pub fn with_new_path(&self, new_content: PathBuf) -> OutputKind {
        match self {
            OutputKind::Internal(_) => OutputKind::Internal(new_content),
            OutputKind::Resource(_) => OutputKind::Resource(new_content),
            OutputKind::Readme(_) => OutputKind::Readme(new_content),
            OutputKind::Meta(_) => OutputKind::Meta(new_content),
            OutputKind::Flags(_) => OutputKind::Flags(new_content),
        }
    }
    pub fn get_filename(&self) -> &Path {
        match self {
            OutputKind::Internal(name) => name,
            OutputKind::Resource(name) => name,
            OutputKind::Readme(name) => name,
            OutputKind::Meta(name) => name,
            OutputKind::Flags(_) => Path::new(DEFAULT_FLAGS_FILENAME),
        }
    }
    pub const fn kind(&self) -> &str {
        match self {
            OutputKind::Internal(_) => "internal",
            OutputKind::Resource(_) => "resource",
            OutputKind::Readme(_) => "readme",
            OutputKind::Meta(_) => "meta",
            OutputKind::Flags(_) => "flags",
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct FlagConfig {
    #[serde(default = "PureRandom::default")]
    pub pure_random: PureRandom,
    pub user_derived: UserDerived,
    pub rng_seed: RngSeed,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PureRandom {
    pub length: u8,
}
impl Default for PureRandom {
    fn default() -> Self {
        PureRandom {
            length: DEFAULT_RANDOM_FLAG_LENGTH,
        }
    }
}
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UserDerived {
    #[serde(default = "flag_generator::Algorithm::default")]
    pub algorithm: flag_generator::Algorithm,
    pub secret: String,
}
impl Default for UserDerived {
    fn default() -> Self {
        UserDerived {
            algorithm: flag_generator::Algorithm::default(),
            secret: { random_hex_secret() },
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RngSeed {
    pub secret: String,
}
impl Default for RngSeed {
    fn default() -> Self {
        RngSeed {
            secret: { random_hex_secret() },
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Deployment {
    #[serde(default = "Deployment::default_build_timeout")]
    pub build_timeout: u32,
    #[serde(default)]
    pub upload: Upload,
}

impl Default for Deployment {
    fn default() -> Self {
        Deployment {
            build_timeout: DEFAULT_BUILD_TIMEOUT,
            upload: Upload::default(),
        }
    }
}
impl Deployment {
    pub fn default_build_timeout() -> u32 {
        DEFAULT_BUILD_TIMEOUT
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "UPPERCASE")]
pub struct Upload {
    pub aws_s3_endpoint: String,
    pub aws_region: String,
    pub bucket_name: String,
    pub use_pre_signed: bool,
    pub link_expiration: u32,
    pub file_expiration: u32,
}
impl Default for Upload {
    fn default() -> Self {
        Upload {
            aws_s3_endpoint: "".to_string(),
            aws_region: "".to_string(),
            bucket_name: "".to_string(),
            use_pre_signed: false,
            link_expiration: DEFAULT_LINK_EXPIRATION,
            file_expiration: DEFAULT_FILE_EXPIRATION,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[non_exhaustive]
#[serde(rename_all = "lowercase")]
pub enum Builder {
    Nix(Nix),
    Shell(Shell),
}
impl Builder {
    pub const fn to_str(&self) -> &str {
        match self {
            Builder::Nix(_) => "nix",
            Builder::Shell(_) => "shell",
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Nix {
    #[serde(default = "Nix::default_entrypoint")]
    pub entrypoint: String,
}
impl Nix {
    pub fn default_entrypoint() -> String {
        DEFAULT_NIX_FILENAME.to_string()
    }
}

impl Default for Nix {
    fn default() -> Self {
        Nix {
            entrypoint: DEFAULT_NIX_FILENAME.to_string(),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Shell {
    #[serde(default = "Shell::default_entrypoint")]
    pub entrypoint: String,
}
impl Shell {
    pub fn default_entrypoint() -> String {
        DEFAULT_SH_FILENAME.to_string()
    }
}

impl Default for Shell {
    fn default() -> Self {
        Shell {
            entrypoint: Self::default_entrypoint(),
        }
    }
}

pub fn check_toml(module: ModuleConfiguration) -> Result<ModuleConfiguration, ConfigError> {
    let module_name = &module.name;
    if module_name.is_empty() {
        return Err(ConfigError::CourseNameError);
    }
    let module_version = &module.version;
    if module_version.is_empty() {
        return Err(ConfigError::CourseVersionError);
    }

    // check number uniques
    let numbers = module
        .categories
        .iter()
        .map(|category| category.number)
        .collect::<std::collections::HashSet<u8>>();
    if numbers.len() != module.categories.len() {
        return Err(ConfigError::CategoryNumberError);
    }
    // Use set to check module task id uniques
    let mut task_ids = HashSet::new();

    // Check each task in each category
    for category in &module.categories {
        for task in &category.tasks {
            for id in task.get_task_ids() {
                if !task_ids.insert(id) {
                    return Err(ConfigError::TaskCountError);
                }
            }
        }
        for task in &category.tasks {
            let _task_result = check_task(task)?;
        }
    }
    // Continue
    Ok(module)
}

pub fn check_task(task: &Task) -> Result<bool, ConfigError> {
    if task.id.is_empty() {
        return Err(ConfigError::TasksIDsNotUniqueError);
    }

    if task.name.is_empty() {
        return Err(ConfigError::TaskNameError);
    }
    if task.points.is_sign_negative() {
        return Err(ConfigError::TaskPointError);
    }
    if task.stages.is_empty() {
        return Err(ConfigError::StageError("Empty stage"));
    }

    for part in &task.stages {
        if task.stages.len() > 1 {
            if part.id.is_none() {
                return Err(ConfigError::StageError(
                    "ID cannot be empty if you have more than one stages.",
                ));
            }
            if let Some(id) = &part.id {
                if !id.to_lowercase().starts_with(&task.id.to_lowercase()) {
                    return Err(ConfigError::StageError(
                        "Stage ID must be prefixed with task ID",
                    ));
                }
            }
        } else if part.id.is_some() {
            // Single element in parts, id must be none
            return Err(ConfigError::StageError(
                "You cannot have ID for stage when you have just one stage.",
            ));
        }
    }

    //checks subtasks have unique id
    if task.stages.len() > 1 {
        let mut set = HashSet::new();
        if !&task
            .stages
            .iter()
            .all(|item| set.insert(item.id.as_ref().unwrap()))
        {
            return Err(ConfigError::StageError("Stages must have unique id!"));
        }

        let all_names_are_non_empty = &task
            .stages
            .iter()
            .all(|s| !s.name.as_ref().unwrap_or(&"".to_string()).is_empty());
        if !all_names_are_non_empty {
            return Err(ConfigError::StageError("Each stage must have name!"));
        }
    } else {
        // Check that metadata fields are not present for single-stage tasks
        let stage = &task.stages[0];
        if stage.id.is_some()
            || stage.name.is_some()
            || stage.description.is_some()
            || stage.weight.is_some()
        {
            return Err(ConfigError::StageError(
                "Single-stage tasks should not have ID, name, description, or weight specified",
            ));
        }
    }

    Ok(true)
}
//TODO: Add warnings for unspecified fields
pub fn read_check_toml(filepath: &OsStr) -> Result<ModuleConfiguration, ConfigError> {
    let mut file = File::open(filepath).map_err(|err| ConfigError::TomlParseError {
        message: format!("Failed to open file: {}", err),
    })?;

    let mut file_content = String::new();
    file.read_to_string(&mut file_content)
        .map_err(|err| ConfigError::TomlParseError {
            message: format!("Failed to read file content: {}", err),
        })?;
    let module_config =
        toml::from_str(&file_content).map_err(|err| ConfigError::TomlParseError {
            message: err.to_string(),
        })?;
    check_toml(module_config)
}
#[cfg(test)]
mod tests {
    use insta::assert_debug_snapshot;

    use super::{Deployment, ModuleConfiguration};

    #[test]
    fn test_toml() {
        let default = include_str!("../tests/data/configs/default.toml");
        let result: ModuleConfiguration = toml::from_str(default).unwrap();
        assert_debug_snapshot!(result);
    }

    #[test]
    fn test_batch_deserialization() {
        let batch_config_with_count = include_str!("../tests/data/configs/batch_count.toml");
        let result: ModuleConfiguration = toml::from_str(batch_config_with_count).unwrap();
        assert_debug_snapshot!(result);
        let no_batch = include_str!("../tests/data/configs/no_batch.toml");
        let result: ModuleConfiguration = toml::from_str(no_batch).unwrap();
        assert_debug_snapshot!(result);
    }
    #[test]
    fn test_disabled_build_modes() {
        let config = include_str!("../tests/data/configs/no_sequential.toml");
        let result: ModuleConfiguration = toml::from_str(config).unwrap();
        assert_debug_snapshot!(result);
        // Invalid mode
        let modified_config = config.replace("sequential", "sequentiall");
        let result: Result<ModuleConfiguration, _> = toml::from_str(&modified_config);
        assert!(result.is_err())
    }
    #[test]
    fn test_deployment_upload_config() {
        let config = include_str!("../tests/data/configs/deployment_upload.toml");
        let result: Deployment = toml::from_str(config).unwrap();
        assert_debug_snapshot!(result);
    }
}
