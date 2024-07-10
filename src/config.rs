use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fs::File;
use std::io::Read;

#[derive(Deserialize)]
pub struct CourseConfiguration {
    course_identifier: CourseIdentifier,
    weeks: Vec<Weeks>,
    tasks: Vec<WeeksTasks>,
    taskbuild: Vec<WeeksTasksBuild>,
    taskoutput: Vec<WeeksTasksOutput>,
}

impl CourseConfiguration {
    pub fn new(
        course_identifier: CourseIdentifier,
        weeks: Vec<Weeks>,
        tasks: Vec<WeeksTasks>,
        taskbuild: Vec<WeeksTasksBuild>,
        taskoutput: Vec<WeeksTasksOutput>,
    ) -> CourseConfiguration {
        CourseConfiguration {
            course_identifier,
            weeks,
            tasks,
            taskbuild,
            taskoutput,
        }
    }
}

#[derive(Deserialize)]
pub struct CourseIdentifier {
    //TODO:Change to UUID
    identifier: String,
    name: String,
    description: String,
    version: String,
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
    number: i32,
    theme: String,
}

impl Weeks {
    pub fn new(number: i32, theme: String) -> Weeks {
        Weeks { number, theme }
    }
}
#[derive(Deserialize)]
pub struct WeeksTasks {
    id: String,
    name: String,
    description: String,
    points: f32,
    flags: Vec<FlagConfig>,
    subtasks: Vec<SubTask>,
}

impl WeeksTasks {
    pub fn new(
        id: String,
        name: String,
        description: String,
        points: f32,
        flags: Vec<FlagConfig>,
        subtasks: Vec<SubTask>,
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
    flag_type: String,
    id: String,
}

impl FlagConfig {
    pub fn new(flag_type: String, id: String) -> FlagConfig {
        FlagConfig { flag_type, id }
    }
}

#[derive(Deserialize)]
pub struct SubTask {
    id: String,
    name: String,
    description: String,
    subpoints: f32,
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
#[derive(Deserialize)]
pub struct WeeksTasksBuild {
    directory: String,
    entrypoint: String,
    builder: String,
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
#[derive(Deserialize)]
pub struct WeeksTasksOutput {
    name: String,
    output_type: String,
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

pub fn check_toml() -> bool {
    return true;
}
