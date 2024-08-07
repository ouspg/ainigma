//File for initializing the build process
use crate::config::CourseConfiguration;
use crate::flag_gen;
use std::error::Error;

pub fn identify_flag_types_for_task(
    course_config: CourseConfiguration,
    week_number: usize,
    task_id: String,
) {
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
    for (i, week) in course_config.weeks.iter().enumerate() {
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
