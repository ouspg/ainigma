use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fs::File;
use std::io::Read;

#[derive(Deserialize,Clone)]

pub struct CourseConfiguration {
    pub course_identifier: CourseIdentifier,
    pub weeks: Vec<Weeks>,
    pub tasks: Vec<WeeksTasks>,
    pub taskbuild: WeeksTasksBuild,
    pub taskoutput: Vec<WeeksTasksOutput>,
}

impl CourseConfiguration {
    pub fn new(course_identifier: CourseIdentifier, weeks: Vec<Weeks>, tasks: Vec<WeeksTasks>, taskbuild: WeeksTasksBuild, taskoutput: Vec<WeeksTasksOutput>) -> CourseConfiguration {
        CourseConfiguration {
            course_identifier,
            weeks,
            tasks,
            taskbuild,
            taskoutput,
        }
    }
}

#[derive(Deserialize,Clone)]
pub struct CourseIdentifier {
    //Change to UUID
    pub identifier: String,
    pub name: String,
    pub description: String,
    pub version: String,
}

impl CourseIdentifier {
    pub fn new(identifier: String, name: String, description: String, version: String) -> CourseIdentifier {
        CourseIdentifier {
            identifier,
            name,
            description,
            version,
        }
    }
}
#[derive(Deserialize,Clone)]
pub struct Weeks {
    pub number: i32,
    pub theme: String,
}

impl Weeks {
    pub fn new(number: i32, theme: String) -> Weeks {
        Weeks {
            number,
            theme,
        }
    }
}
#[derive(Deserialize,Clone)]
pub struct WeeksTasks {
    pub id: String,
    pub name: String,
    pub description: String,
    pub points: f32,
    pub flags: Vec<Flag>,
    pub subtasks: Vec<SubTask>,
}

impl WeeksTasks {
    pub fn new(id: String, name: String, description: String, points: f32, flags: Vec<Flag>, subtasks: Vec<SubTask>) -> WeeksTasks {
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
#[derive(Deserialize,Clone)]
pub struct Flag {
    pub flag_type: String,
    pub id: String,
}

impl Flag {
    pub fn new(flag_type: String, id: String) -> Flag {
        Flag {
            flag_type,
            id,
        }
    }
}

#[derive(Deserialize,Clone)]
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
#[derive(Deserialize,Clone)]
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
#[derive(Deserialize,Clone)]
pub struct WeeksTasksOutput {
    pub name: String,
    pub output_type: String,
}

impl WeeksTasksOutput {
    pub fn new(name: String, output_type: String) -> WeeksTasksOutput {
        WeeksTasksOutput {
            name,
            output_type,
        }
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
