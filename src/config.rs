use serde::Deserialize;
use std::collections::HashSet;
use std::fs::File;
use std::io::Read;
use std::error::Error;
use uuid::Uuid;

use crate::flag_generator;

#[derive(Debug)]
pub enum ConfigError {
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

#[derive(Deserialize,Clone)]
pub struct CourseConfiguration {
    pub course_identifier: CourseIdentifier,
    pub weeks: Vec<Weeks>,
    pub flag_types: FlagsTypes,
}

impl CourseConfiguration {
    pub fn new(
        course_identifier: CourseIdentifier,
        weeks: Vec<Weeks>,
        flag_types: FlagsTypes,
    ) -> CourseConfiguration {
        CourseConfiguration {
            course_identifier,
            weeks,
            flag_types,
        }
    }
}

#[derive(Deserialize, Clone)]
pub struct CourseIdentifier {
    //TODO:Change to UUID
    pub identifier: String,
    pub name: String,
    pub description: String,
    pub version: String,
}

impl CourseIdentifier {
    pub fn new(
        identifier: String,
        name: String,
        description: String,
        version: String,
    ) -> CourseIdentifier {
        CourseIdentifier {
            identifier,
            name,
            description,
            version,
        }
    }
}
#[derive(Deserialize, Clone)]
pub struct Weeks {
    pub tasks: Vec<Tasks>,
    pub number: u8,
    pub theme: String,
}

impl Weeks {
    pub fn new(tasks: Vec<Tasks>, number: u8, theme: String) -> Weeks {
        Weeks {
            tasks,
            number,
            theme,
        }
    }
}
#[derive(Deserialize, Clone)]
pub struct Tasks {
    pub id: String,
    pub name: String,
    pub description: String,
    pub points: f32,
    pub flag_types: Vec<FlagConfig>,
    pub subtasks: Option<Vec<SubTask>>,
    pub build: WeeksTasksBuild,
}

impl Tasks {
    pub fn new(
        id: String,
        name: String,
        description: String,
        points: f32,
        flag_types: Vec<FlagConfig>,
        subtasks: Option<Vec<SubTask>>,
        build: WeeksTasksBuild,
    ) -> Tasks {
        Tasks {
            id,
            name,
            description,
            points,
            flag_types,
            subtasks,
            build,
        }
    }
}
#[derive(Deserialize, Clone)]
pub struct FlagConfig {
    pub flag_type: String,
    pub id: String,
}

impl FlagConfig {
    pub fn new(flag_type: String, id: String) -> FlagConfig {
        FlagConfig { flag_type, id }
    }
}

#[derive(Deserialize, Clone)]
pub struct SubTask {
    pub id: String,
    pub name: String,
    pub description: String,
    pub subpoints: f32,
}

impl SubTask {
    pub fn new(
        id: String,
        name: String,
        description: String,
        subpoints: f32,
    ) -> SubTask {
        SubTask {
            id,
            name,
            description,
            subpoints,
        }
    }
}
#[derive(Deserialize, Clone)]
pub struct WeeksTasksBuild {
    pub directory: String,
    pub entrypoint: String,
    pub builder: String,
    pub output: Vec<WeeksTasksOutput>,
}

impl WeeksTasksBuild {
    pub fn new(
        directory: String,
        entrypoint: String,
        builder: String,
        output: Vec<WeeksTasksOutput>,
    ) -> WeeksTasksBuild {
        WeeksTasksBuild {
            directory,
            entrypoint,
            builder,
            output,
        }
    }
}
#[derive(Deserialize, Clone)]
pub struct WeeksTasksOutput {
    pub name: String,
    pub output_type: String,
}

impl WeeksTasksOutput {
    pub fn new(name: String, output_type: String) -> WeeksTasksOutput {
        WeeksTasksOutput { name, output_type }
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
pub fn read_toml_content_from_file(filepath: &str) -> Result<String, Box<dyn Error>> {
    let mut file = File::open(filepath)?;
    let mut file_content = String::new();
    file.read_to_string(&mut file_content)?;
    Ok(file_content)
}

//TODO: Add warnings for unspecified fields
pub fn toml_content(file_content: String) -> Result<CourseConfiguration, ConfigError> {
    let course_config = toml::from_str(&file_content);
    match course_config {
        Ok(val) => return Ok(val),
        Err(err) => {
            return Err(ConfigError::TomlParseError {
                message: err.to_string(),
            })
        }
    }
}

pub fn check_toml(course: CourseConfiguration) -> Result<CourseConfiguration, ConfigError> {
    let id = course.course_identifier.identifier.as_str();
    let mut result: [u8; 16] = [0; 16];
    // Uuid check removable when id is Uuid
    for (i, hex_byte) in id.as_bytes().chunks(2).enumerate() {
        let byte_str = String::from_utf8_lossy(hex_byte);
        let byte_value = u8::from_str_radix(&byte_str, 16).unwrap();
        result[i] = byte_value;
    }
    let _course_id = Uuid::from_bytes(result);
    let course_name = &course.course_identifier.name;
    if course_name.is_empty() {
        return Err(ConfigError::CourseNameError);
    }
    let course_version = &course.course_identifier.version;
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
        task_count = task_count + week.tasks.len();
        for task in &week.tasks {
            let _task_result = check_task(&task)?;
        }
    }
    if task_ids.len() != task_count {
        return Err(ConfigError::TaskCountError);
    }
    // Continue
    return Ok(course);
}

pub fn check_task(task: &Tasks) -> Result<bool, ConfigError> {
    if task.id.is_empty() {
        return Err(ConfigError::TaskIdError);
    }

    if task.name.is_empty() {
        return Err(ConfigError::TaskNameError);
    }
    if task.points.is_sign_negative() {
        return Err(ConfigError::TaskPointError);
    }

    for flag in &task.flag_types {
        // possible flag enum later
        if !(flag.flag_type == "user_derived"
            || flag.flag_type == "pure_random"
            || flag.flag_type == "rng_seed")
        {
            return Err(ConfigError::FlagTypeError);
        }
    }
    // checks flags have unique id
    let ids = task
        .flag_types
        .iter()
        .map(|flag| flag.id.clone())
        .collect::<std::collections::HashSet<String>>();
    if ids.len() != task.flag_types.len() {
        return Err(ConfigError::FlagCountError);
    }
    if task.subtasks.is_some() {
        //checks subtasks have unique id
        let subtasks = task.subtasks.as_ref().unwrap();
        let sub_id = subtasks
            .iter()
            .map(|subtask| subtask.id.clone())
            .collect::<std::collections::HashSet<String>>();
        if sub_id.len() != subtasks.len() {
            return Err(ConfigError::SubTaskCountError);
        }
        // checks subtasks have match id with flags
        let subtasks2 = task.subtasks.as_ref().unwrap();
        if !(subtasks2
            .iter()
            .zip(task.flag_types.iter())
            .all(|(a, b)| a.id == b.id))
        {
            return Err(ConfigError::SubTaskIdMatchError);
        }
        // checks subtasks have a name
        let subtasks3 = task.subtasks.as_ref().unwrap();
        let all_names_are_non_empty = subtasks3.iter().all(|s| !s.name.is_empty());
        if !all_names_are_non_empty {
            return Err(ConfigError::SubTaskNameError);
        }
        // checks subtask point count matches
        let sub_points = task
            .subtasks
            .as_ref()
            .unwrap()
            .iter()
            .map(|subtask| subtask.subpoints)
            .sum();
        if (task.points as f32) != sub_points {
            return Err(ConfigError::SubTaskPointError);
        }
    }
    return Ok(true);
}

pub fn read_check_toml(filepath: &str) -> Result<CourseConfiguration, ConfigError> {
    let tomlstring = read_toml_content_from_file(filepath).expect("No reading errors");
    let courseconfig = toml_content(tomlstring)?;
    let result = check_toml(courseconfig);
    match result {
        Ok(val) => return Ok(val),
        Err(err) => return Err(err),
    }
}
#[cfg(test)]
mod tests {
    use super::{check_toml, toml_content};
    use crate::config::read_toml_content_from_file;

    #[test]
    fn test_toml() {
        let result = read_toml_content_from_file("course_test.toml");
        let result1 = toml_content(result.unwrap());
        let courseconfig = result1.unwrap();
        let _coursefconfig = check_toml(courseconfig).unwrap();
    }
}