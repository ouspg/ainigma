use serde::Deserialize;
use std::collections::HashSet;
use std::error::Error;
use std::ffi::OsStr;
use std::fmt;
use std::fs::File;
use std::io::Read;
use uuid::Uuid;

use crate::flag_generator;

#[derive(Debug)]
pub enum ConfigError {
    UuidError,
    TomlParseError { message: String },
    CourseNameError,
    CourseVersionError,
    WeekNumberError,
    TaskIdError,
    TaskCountError,
    TaskNameError,
    TaskPointError,
    FlagTypeError,
    FlagCountError,
    SubTaskCountError,
    SubTaskIdMatchError,
    SubTaskPointError,
    SubTaskNameError,
}
impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConfigError::UuidError => write!(f, "Error in Toml file: Course Uuid must be valid"),
            ConfigError::TomlParseError { message } => write!(f, "{}", message),
            ConfigError::CourseNameError => {
                write!(f, "Error in Toml file: Course name must not be empty")
            }
            ConfigError::CourseVersionError => {
                write!(f, "Error in Toml file: Course version must not be empty")
            }
            ConfigError::WeekNumberError => {
                write!(f, "Error in Toml file: Each week must have a unique number")
            }
            ConfigError::TaskIdError => {
                write!(f, "Error in Toml file: Task Id cannot be empty")
            }
            ConfigError::TaskCountError => write!(f, "Error in Toml file: Each task must have a unique id"),
            ConfigError::TaskNameError => write!(f, "Error in Toml file: Task name cannot be empty"),
            ConfigError::TaskPointError => write!(f, "Error in Toml file: Task point amount must be non-negative"),
            ConfigError::FlagTypeError => write!(f, "Error in Toml file: Flag type must be one of the three \"user_derived\", \"pure_random\", \"rng_seed\""),
            ConfigError::FlagCountError => write!(f, "Error in Toml file: Task flags must have a unique id"),
            ConfigError::SubTaskCountError => write!(f, "Error in Toml file: Each task subtask must have a unique id"),
            ConfigError::SubTaskIdMatchError => write!(f,"Error in Toml file: Each task subtask must have a unique matching id with subtask flag"),
            ConfigError::SubTaskPointError => write!(f, "Error in Toml file: Each task points much match subtask point total"),
            ConfigError::SubTaskNameError => write!(f, "Error in Toml file: Each task subtask name must not be empty"),
        }
    }
}

#[derive(Deserialize, Clone)]
pub struct CourseConfiguration {
    //TODO:Change to UUID
    pub identifier: String,
    pub name: String,
    pub description: String,
    pub version: String,
    pub weeks: Vec<Week>,
    pub flag_types: FlagsTypes,
}

impl CourseConfiguration {
    pub fn new(
        identifier: String,
        name: String,
        description: String,
        version: String,
        weeks: Vec<Week>,
        flag_types: FlagsTypes,
    ) -> CourseConfiguration {
        CourseConfiguration {
            identifier,
            name,
            description,
            version,
            weeks,
            flag_types,
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

#[derive(Deserialize, Clone)]
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

#[derive(Deserialize, Clone)]
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
}

#[derive(Deserialize, Clone)]
#[non_exhaustive]
pub struct FlagConfiguration {
    pub kind: String,
}

#[derive(Deserialize, Clone)]
pub struct TaskElement {
    pub id: Option<String>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub weight: Option<u8>,
    pub flag: FlagConfiguration,
}

impl TaskElement {
    pub fn new(
        id: Option<String>,
        name: Option<String>,
        description: Option<String>,
        weight: Option<u8>,
        flag: FlagConfiguration,
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
#[derive(Deserialize, Clone)]
pub struct BuildConfig {
    pub directory: String,
    pub entrypoint: String,
    pub builder: String,
    pub output: Vec<BuildOutputFile>,
}

impl BuildConfig {
    pub fn new(
        directory: String,
        entrypoint: String,
        builder: String,
        output: Vec<BuildOutputFile>,
    ) -> BuildConfig {
        BuildConfig {
            directory,
            entrypoint,
            builder,
            output,
        }
    }
}
#[derive(Deserialize, Clone)]
pub struct BuildOutputFile {
    pub name: String,
    // TODO create own type
    pub kind: String,
}

impl BuildOutputFile {
    pub fn new(name: String, kind: String) -> BuildOutputFile {
        BuildOutputFile { name, kind }
    }
}

#[derive(Deserialize, Clone)]
pub struct FlagsTypes {
    pub pure_random: PureRandom,
    pub user_derived: UserDerived,
    pub rng_seed: RngSeed,
}
#[derive(Deserialize, Clone)]
pub struct PureRandom {
    pub length: u8,
}
#[derive(Deserialize, Clone)]
pub struct UserDerived {
    pub algorithm: flag_generator::Algorithm,
    pub secret: String,
}
#[derive(Deserialize, Clone)]
pub struct RngSeed {
    pub secret: String,
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
    // check course task id uniques
    let mut task_ids = HashSet::new();
    let mut task_count: usize = 0;

    // Check each task in each week
    for week in &course.weeks {
        let week_ids = week
            .tasks
            .iter()
            .map(|task| task.id.clone())
            .collect::<std::collections::HashSet<String>>();
        task_ids.extend(week_ids);
        task_count += week.tasks.len();
        for task in &week.tasks {
            let _task_result = check_task(task)?;
        }
    }
    if task_ids.len() != task_count {
        return Err(ConfigError::TaskCountError);
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
