use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::Read;
use std::{error::Error, fmt::format};
use uuid::{uuid, Uuid};

use crate::flag_generator::Flag;

#[derive(Deserialize,Clone)]

pub struct CourseConfiguration {
    pub course_identifier: CourseIdentifier,
    pub weeks: Vec<Weeks>,
<<<<<<< HEAD
    pub taskbuild: Vec<WeeksTasksBuild>,
=======
    pub tasks: Vec<WeeksTasks>,
    pub taskbuild: WeeksTasksBuild,
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
    pub taskoutput: Vec<WeeksTasksOutput>,
}

impl CourseConfiguration {
<<<<<<< HEAD
    pub fn new(
        course_identifier: CourseIdentifier,
        weeks: Vec<Weeks>,
        taskbuild: Vec<WeeksTasksBuild>,
        taskoutput: Vec<WeeksTasksOutput>,
    ) -> CourseConfiguration {
=======
    pub fn new(course_identifier: CourseIdentifier, weeks: Vec<Weeks>, tasks: Vec<WeeksTasks>, taskbuild: WeeksTasksBuild, taskoutput: Vec<WeeksTasksOutput>) -> CourseConfiguration {
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
        CourseConfiguration {
            course_identifier,
            weeks,
            taskbuild,
            taskoutput,
        }
    }
}

#[derive(Deserialize,Clone)]
pub struct CourseIdentifier {
<<<<<<< HEAD
    //TODO:Change to UUID
=======
    //Change to UUID
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
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
<<<<<<< HEAD
    pub tasks: Vec<WeeksTasks>,
=======
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
    pub number: i32,
    pub theme: String,
}

impl Weeks {
<<<<<<< HEAD
    pub fn new(tasks: Vec<WeeksTasks>, number: i32, theme: String) -> Weeks {
        Weeks {
            tasks,
=======
    pub fn new(number: i32, theme: String) -> Weeks {
        Weeks {
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
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
<<<<<<< HEAD
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
=======
    pub flags: Vec<Flag>,
    pub subtasks: Vec<SubTask>,
}

impl WeeksTasks {
    pub fn new(id: String, name: String, description: String, points: f32, flags: Vec<Flag>, subtasks: Vec<SubTask>) -> WeeksTasks {
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
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
<<<<<<< HEAD
#[derive(Deserialize)]
pub struct FlagConfig {
=======
#[derive(Deserialize,Clone)]
pub struct Flag {
>>>>>>> e05ba41fc8ced75fcdf6946c1e93b172b71ff364
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

pub fn check_toml(course_config: CourseConfiguration) -> Result<bool, Box<dyn Error>> {
    let course = course_config;
    let id = course.course_identifier.identifier.as_str();
    let mut result: [u8; 16] = [0; 16];

    for (i, hex_byte) in id.as_bytes().chunks(2).enumerate() {
        let byte_str = String::from_utf8_lossy(hex_byte);
        let byte_value = u8::from_str_radix(&byte_str, 16).unwrap();
        result[i] = byte_value;
    }
    let course_id = Uuid::from_bytes(result);
    let course_name = course.course_identifier.name;
    if course_name.is_empty() {
        panic!("Empty course name");
    }

    return Ok(true);
}
