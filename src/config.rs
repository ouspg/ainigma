use crate::flag_generator;
use serde::Deserialize;
use std::collections::HashSet;
use std::error::Error;
use std::ffi::OsStr;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use thiserror::Error;
use uuid::Uuid;

const DEFAULT_NIX_FILENAME: &str = "flake.nix";
const DEFAULT_SH_FILENAME: &str = "entrypoint.sh";

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("Error in Toml file: Course Uuid must be valid")]
    UuidError,
    #[error("{message}")]
    TomlParseError { message: String },
    #[error("Error in Toml file: Course name must not be empty")]
    CourseNameError,
    #[error("Error in Toml file: Course version must not be empty")]
    CourseVersionError,
    #[error("Error in Toml file: Each week must have a unique number")]
    WeekNumberError,
    #[error("Error in Toml file: Task Id cannot be empty")]
    TaskIdError,
    #[error("Error in Toml file: Each task must have a unique id")]
    TaskCountError,
    #[error("Error in Toml file: Task name cannot be empty")]
    TaskNameError,
    #[error("Error in Toml file: Task point amount must be non-negative")]
    TaskPointError,
    #[error("Error in Toml file: Flag type must be one of the three \"user_derived\", \"pure_random\", \"rng_seed\"")]
    FlagTypeError,
    #[error("Error in Toml file: Task flags must have a unique id")]
    FlagCountError,
    #[error("Error in Toml file: Each task subtask must have a unique ID")]
    SubTaskCountError,
    #[error("Error in Toml file: Each subtask ID must include the current task ID as prefix")]
    SubTaskIdMatchError,
    #[error("Error in Toml file: Each task points must match subtask point total")]
    SubTaskPointError,
    #[error("Error in Toml file: Each task subtask name must not be empty")]
    SubTaskNameError,
}

#[derive(Debug, Deserialize, Clone)]
pub struct CourseConfiguration {
    //TODO:Change to UUID
    pub identifier: String,
    pub name: String,
    pub description: String,
    pub version: String,
    pub weeks: Vec<Week>,
    pub flag_types: FlagsTypes,
    pub deployment: Deployment,
}

impl CourseConfiguration {
    pub fn new(
        identifier: String,
        name: String,
        description: String,
        version: String,
        weeks: Vec<Week>,
        flag_types: FlagsTypes,
        deployment: Deployment,
    ) -> CourseConfiguration {
        CourseConfiguration {
            identifier,
            name,
            description,
            version,
            weeks,
            flag_types,
            deployment,
        }
    }
    pub fn get_task_by_id(&self, id: &str) -> Option<&Task> {
        for week in &self.weeks {
            for task in &week.tasks {
                if task.id == id {
                    return Some(task);
                }
            }
        }
        None
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct Week {
    pub tasks: Vec<Task>,
    pub number: u8,
    pub theme: String,
}

impl Week {
    pub fn new(tasks: Vec<Task>, number: u8, theme: String) -> Week {
        Week {
            tasks,
            number,
            theme,
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct Task {
    pub id: String,
    pub name: String,
    pub description: String,
    pub points: f32,
    pub stages: Vec<TaskElement>,
    pub build: BuildConfig,
}

impl Task {
    pub fn new(
        id: String,
        name: String,
        description: String,
        points: f32,
        stages: Vec<TaskElement>,
        build: BuildConfig,
    ) -> Task {
        Task {
            id,
            name,
            description,
            points,
            stages,
            build,
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

#[derive(Debug, Deserialize, Clone)]
#[non_exhaustive]
pub struct FlagConfig {
    pub kind: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct TaskElement {
    pub id: Option<String>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub weight: Option<u8>,
    pub flag: FlagConfig,
}

impl TaskElement {
    pub fn new(
        id: Option<String>,
        name: Option<String>,
        description: Option<String>,
        weight: Option<u8>,
        flag: FlagConfig,
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
#[derive(Debug, Deserialize, Clone)]
pub struct BuildConfig {
    pub directory: std::path::PathBuf,
    pub builder: Builder,
    pub output: Vec<BuildOutputFile>,
}

impl BuildConfig {
    pub fn new(
        directory: std::path::PathBuf,
        builder: Builder,
        output: Vec<BuildOutputFile>,
    ) -> BuildConfig {
        BuildConfig {
            directory,
            builder,
            output,
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct BuildOutputFile {
    pub kind: OutputKind,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "lowercase")]
pub enum OutputKind {
    Internal(PathBuf),
    Resource(PathBuf),
    Readme(PathBuf),
    Meta(PathBuf),
}

impl OutputKind {
    pub fn with_new_path(&self, new_content: PathBuf) -> OutputKind {
        match self {
            OutputKind::Internal(_) => OutputKind::Internal(new_content),
            OutputKind::Resource(_) => OutputKind::Resource(new_content),
            OutputKind::Readme(_) => OutputKind::Readme(new_content),
            OutputKind::Meta(_) => OutputKind::Meta(new_content),
        }
    }
    pub fn get_filename(&self) -> &Path {
        match self {
            OutputKind::Internal(name) => name,
            OutputKind::Resource(name) => name,
            OutputKind::Readme(name) => name,
            OutputKind::Meta(name) => name,
        }
    }
    pub const fn kind(&self) -> &str {
        match self {
            OutputKind::Internal(_) => "internal",
            OutputKind::Resource(_) => "resource",
            OutputKind::Readme(_) => "readme",
            OutputKind::Meta(_) => "meta",
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct FlagsTypes {
    pub pure_random: PureRandom,
    pub user_derived: UserDerived,
    pub rng_seed: RngSeed,
}
#[derive(Debug, Deserialize, Clone)]
pub struct PureRandom {
    pub length: u8,
}
#[derive(Debug, Deserialize, Clone)]
pub struct UserDerived {
    pub algorithm: flag_generator::Algorithm,
    pub secret: String,
}
#[derive(Debug, Deserialize, Clone)]
pub struct RngSeed {
    pub secret: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Deployment {
    pub build_timeout: u32,
    pub upload: Upload,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "UPPERCASE")]
pub struct Upload {
    pub aws_s3_endpoint: String,
    pub aws_region: String,
    pub bucket_name: String,
    pub link_expiration: u32,
    pub file_expiration: u32,
}

#[derive(Debug, Deserialize, Clone)]
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

#[derive(Debug, Deserialize, Clone)]
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

#[derive(Debug, Deserialize, Clone)]
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

pub fn read_toml_content_from_file(filepath: &OsStr) -> Result<String, Box<dyn Error>> {
    let mut file = File::open(filepath)?;
    let mut file_content = String::new();
    file.read_to_string(&mut file_content)?;
    Ok(file_content)
}

//TODO: Add warnings for unspecified fields
pub fn toml_content(file_content: String) -> Result<CourseConfiguration, ConfigError> {
    let course_config = toml::from_str(&file_content);
    course_config.map_err(|err| ConfigError::TomlParseError {
        message: err.to_string(),
    })
}

pub fn check_toml(course: CourseConfiguration) -> Result<CourseConfiguration, ConfigError> {
    let id = course.identifier.as_str();
    match Uuid::parse_str(id) {
        Ok(ok) => ok,
        Err(_err) => return Err(ConfigError::UuidError),
    };
    let course_name = &course.name;
    if course_name.is_empty() {
        return Err(ConfigError::CourseNameError);
    }
    let course_version = &course.version;
    if course_version.is_empty() {
        return Err(ConfigError::CourseVersionError);
    }

    // check number uniques
    let numbers = course
        .weeks
        .iter()
        .map(|week| week.number)
        .collect::<std::collections::HashSet<u8>>();
    if numbers.len() != course.weeks.len() {
        return Err(ConfigError::WeekNumberError);
    }
    // Use set to check course task id uniques
    let mut task_ids = HashSet::new();

    // Check each task in each week
    for week in &course.weeks {
        for task in &week.tasks {
            for id in task.get_task_ids() {
                if !task_ids.insert(id) {
                    return Err(ConfigError::TaskCountError);
                }
            }
        }
        for task in &week.tasks {
            let _task_result = check_task(task)?;
        }
    }
    // Continue
    Ok(course)
}

pub fn check_task(task: &Task) -> Result<bool, ConfigError> {
    if task.id.is_empty() {
        return Err(ConfigError::TaskIdError);
    }

    if task.name.is_empty() {
        return Err(ConfigError::TaskNameError);
    }
    if task.points.is_sign_negative() {
        return Err(ConfigError::TaskPointError);
    }
    if task.stages.is_empty() {
        return Err(ConfigError::SubTaskCountError);
    }

    for part in &task.stages {
        if task.stages.len() > 1 {
            if part.id.is_none() {
                return Err(ConfigError::SubTaskCountError);
            }
            if let Some(id) = &part.id {
                if !id.to_lowercase().starts_with(&task.id.to_lowercase()) {
                    return Err(ConfigError::SubTaskIdMatchError);
                }
            }
        } else if part.id.is_some() {
            // Single element in parts, id must be none
            return Err(ConfigError::SubTaskCountError);
        }
        // possible flag enum later
        if !(part.flag.kind == "user_derived"
            || part.flag.kind == "pure_random"
            || part.flag.kind == "rng_seed")
        {
            return Err(ConfigError::FlagTypeError);
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
            return Err(ConfigError::SubTaskCountError);
        }

        let all_names_are_non_empty = &task
            .stages
            .iter()
            .all(|s| !s.name.as_ref().unwrap_or(&"".to_string()).is_empty());
        if !all_names_are_non_empty {
            return Err(ConfigError::SubTaskNameError);
        }
    } else {
        // id, name, description, weight must be none if just one element in parts
        if task.stages[0].id.is_some() {
            return Err(ConfigError::SubTaskCountError);
        }
        if task.stages[0].name.is_some() {
            return Err(ConfigError::SubTaskNameError);
        }
        if task.stages[0].description.is_some() {
            // TODO change error message
            return Err(ConfigError::SubTaskNameError);
        }
        if task.stages[0].weight.is_some() {
            // TODO change error message
            return Err(ConfigError::SubTaskNameError);
        }
    }

    Ok(true)
}

pub fn read_check_toml(filepath: &OsStr) -> Result<CourseConfiguration, ConfigError> {
    let tomlstring = read_toml_content_from_file(filepath).expect("No reading errors");
    let courseconfig = toml_content(tomlstring)?;
    check_toml(courseconfig)
}
#[cfg(test)]
mod tests {
    use std::ffi::OsStr;

    use super::{check_toml, toml_content};
    use crate::config::read_toml_content_from_file;

    #[test]
    fn test_toml() {
        let result = read_toml_content_from_file(OsStr::new("course.toml"));
        let result1 = toml_content(result.unwrap());
        let courseconfig = result1.unwrap();
        let _coursefconfig = check_toml(courseconfig).unwrap();
    }
}
