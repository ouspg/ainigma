use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs::File;
use std::io::Read;
use std::{error::Error, fmt::format};
use uuid::{uuid, Uuid};

use crate::flag_generator::Flag;

#[derive(Debug)]
pub enum ConfigError {
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
    SubTaskMatchError
}

#[derive(Deserialize)]
pub struct CourseConfiguration {
    pub course_identifier: CourseIdentifier,
    pub weeks: Vec<Weeks>,
    pub taskbuild: Vec<WeeksTasksBuild>,
    pub taskoutput: Vec<WeeksTasksOutput>,
}

impl CourseConfiguration {
    pub fn new(
        course_identifier: CourseIdentifier,
        weeks: Vec<Weeks>,
        taskbuild: Vec<WeeksTasksBuild>,
        taskoutput: Vec<WeeksTasksOutput>,
    ) -> CourseConfiguration {
        CourseConfiguration {
            course_identifier,
            weeks,
            taskbuild,
            taskoutput,
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
#[derive(Deserialize)]
pub struct Weeks {
    pub tasks: Vec<WeeksTasks>,
    pub number: u8,
    pub theme: String,
}

impl Weeks {
    pub fn new(tasks: Vec<WeeksTasks>, number: u8, theme: String) -> Weeks {
        Weeks {
            tasks,
            number,
            theme,
        }
    }
}
#[derive(Deserialize)]
pub struct WeeksTasks {
    pub id: String,
    pub name: String,
    pub description: String,
    pub points: f32,
    pub flags: Vec<FlagConfig>,
    pub subtasks: Option<Vec<SubTask>>,
}

impl WeeksTasks {
    pub fn new(
        id: String,
        name: String,
        description: String,
        points: f32,
        flags: Vec<FlagConfig>,
        subtasks: Option<Vec<SubTask>>,
    ) -> WeeksTasks {
        WeeksTasks {
            id,
            name,
            description,
            points,
            flags,
            subtasks,
        }
    }
}
#[derive(Deserialize)]
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
    pub fn new(id: String, name: String, description: String, subpoints: f32) -> SubTask {
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
}

impl WeeksTasksBuild {
    pub fn new(directory: String, entrypoint: String, builder: String) -> WeeksTasksBuild {
        WeeksTasksBuild {
            directory,
            entrypoint,
            builder,
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

pub fn read_toml_content_from_file(filepath: &str) -> Result<String, Box<dyn Error>> {
    let mut file = File::open(filepath)?;
    let mut file_content = String::new();
    file.read_to_string(&mut file_content)?;
    Ok(file_content)
}

//TODO: Add warnings for unspecified fields
pub fn toml_content(file_content: String) -> Result<CourseConfiguration, Box<dyn Error>> {
    let course_config: CourseConfiguration = toml::from_str(&file_content)?;
    Ok(course_config)
}

pub fn check_toml(course: CourseConfiguration) -> Result<bool, ConfigError> {
    let id = course.course_identifier.identifier.as_str();
    let mut result: [u8; 16] = [0; 16];

    for (i, hex_byte) in id.as_bytes().chunks(2).enumerate() {
        let byte_str = String::from_utf8_lossy(hex_byte);
        let byte_value = u8::from_str_radix(&byte_str, 16).unwrap();
        result[i] = byte_value;
    }
    let _course_id = Uuid::from_bytes(result);
    let course_name = course.course_identifier.name;
    if course_name.is_empty() {
        return Err(ConfigError::CourseNameError);
    }
    let course_version = course.course_identifier.version;
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
    for week in course.weeks {
        let week_ids = week
            .tasks
            .iter()
            .map(|task| task.id.clone())
            .collect::<std::collections::HashSet<String>>();
        task_ids.extend(week_ids);
        task_count = task_count + week.tasks.len();
        for task in week.tasks {
            let _task_result = check_task(task)?;
        }
    }
    if task_ids.len() != task_count {
        return Err(ConfigError::TaskCountError);
    }
    // Continue
    return Ok(true);
}

pub fn check_task(task: WeeksTasks) -> Result<bool, ConfigError> {
    if task.id.is_empty() {
        return Err(ConfigError::TaskIdError);
    }

    if task.name.is_empty() {
        return Err(ConfigError::TaskNameError);
    }
    if task.points.is_sign_negative() {
        return Err(ConfigError::TaskPointError);
    }

    for flag in &task.flags {
        // possible flag enum later
        if !(flag.flag_type == "user_derived"
            || flag.flag_type == "pure_random"
            || flag.flag_type == "rng_seed")
        {
            return Err(ConfigError::FlagTypeError);
        }
    }
    //TODO: CHECK NAME, ID, POINT TOTAL
    let ids = task
        .flags
        .iter()
        .map(|flag| flag.id.clone())
        .collect::<std::collections::HashSet<String>>();
    if ids.len() != task.flags.len() {
        return Err(ConfigError::FlagCountError);
    }
    if task.subtasks.is_some() {
        let subtasks = task.subtasks.as_ref().unwrap();
        let sub_id = subtasks
            .iter()
            .map(|subtask| subtask.id.clone())
            .collect::<std::collections::HashSet<String>>();
        if sub_id.len() != subtasks.len() {
            return Err(ConfigError::SubTaskCountError);
        }
        if !(task
            .subtasks
            .unwrap()
            .iter_mut()
            .zip(task.flags.iter())
            .all(|(a, b)| a.id == b.id))
        {
            return Err(ConfigError::SubTaskMatchError);
        }
    }
    return Ok(true);
}
