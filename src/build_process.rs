//File for initializing the build process
use std::error::Error;
use crate::config::CourseConfiguration;
use crate::flag_gen;
use crate::config;

fn read_and_check_toml_content(config_filepath: &str) -> Result<CourseConfiguration, Box<dyn Error>> {
    let file_content_as_string = course_config::read_toml_content_from_file(config_filepath);
    let toml_content = course_config::toml_content(file_content_as_string).unwrap();
    if(course_config::check_toml(toml_content)) {
        return Ok(toml_content);
    } else {
        return Err("Error in toml file");
    }
}

pub fn identify_flag_types_for_task(course_config: CourseConfiguration, week_number: usize, task_id: String) {
    for week in course_config.weeks.iter() {
        if week.number == week_number {
            for task in week.tasks.iter() {
                if task.id == task_id {
                    if task.subtasks.is_some() {
                        for subtask in task.subtasks.iter() {
                            for flag_type in task.flag_types.iter() {
                                if flag_type.id == subtask.id {
                                    subtask.flag_type = flag_type;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

pub fn identify_flag_types_for_week(course_config: CourseConfiguration, week_number: usize) {
    for week in course_config.weeks.iter() {
        if week.number == week_number {
            for task in week.tasks.iter() {
                if task.subtasks.is_some() {
                    for subtask in task.subtasks.iter() {
                        for flag_type in task.flag_types.iter() {
                            if flag_type.id == subtask.id {
                                subtask.flag_type = flag_type;
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}

pub fn identify_all_flag_types(course_config: CourseConfiguration) {
        for (i,week) in course_config.weeks.iter().enumerate() {
            if week.tasks[i].subtasks.is_some() {
            for (j, subtask) in week.tasks[i].subtasks.iter().enumerate() {
                for flag_type in week.tasks[i].flag_types.iter() {
                    if flag_type.id == subtask[j].id {
                        subtask[j].flag_type = flag_type;
                        break;
                    }
            }
        }
    } 
}
}