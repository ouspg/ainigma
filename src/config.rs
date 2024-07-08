use serde::{Deserialize, Serialize};
use std::fs;
use std::error::Error;
use uuid::Uuid;

#[derive(Deserialize)]
struct CourseConfiguration {
    course_identifier: CourseIdentifier,
    weeks: Vec<Weeks>,
    tasks: Vec<WeeksTasks>,
    taskbuild: Vec<WeeksTasksBuild>,
    taskoutput: Vec<WeeksTasksOutput>,
}

impl CourseConfiguration {
    pub fn new(course_identifier: CourseIdentifier, weeks: Vec<Weeks>, tasks: Vec<WeeksTasks>, taskbuild: Vec<WeeksTasksBuild>, taskoutput: Vec<WeeksTasksOutput>) -> CourseConfiguration {
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
struct CourseIdentifier {
    //TODO:Change to UUID
    identifier: String,
    name: String,
    description: String,
    version: String,
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
#[derive(Deserialize)]
struct Weeks {
    number: i32,
    theme: String,
}

impl Weeks {
    pub fn new(number: i32, theme: String) -> Weeks {
        Weeks {
            number,
            theme,
        }
    }
}
#[derive(Deserialize)]
struct WeeksTasks {
    id: String,
    name: String,
    description: String,
    points: f32,
    flags: Vec<Flag>,
    subtasks: Vec<SubTask>,
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
#[derive(Deserialize)]
struct Flag {
    flag_type: String,
    id: String,
}

impl Flag {
    pub fn new(flag_type: String, id: String) -> Flag {
        Flag {
            flag_type,
            id,
        }
    }
}

#[derive(Deserialize)]
struct SubTask {
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
struct WeeksTasksBuild {
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
struct WeeksTasksOutput {
    name: String,
    output_type: String,
}

impl WeeksTasksOutput {
    pub fn new(name: String, output_type: String) -> WeeksTasksOutput {
        WeeksTasksOutput {
            name,
            output_type,
        }
    }
}
