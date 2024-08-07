//File for initializing the build process
use crate::config::CourseConfiguration;
use crate::flag_generator;

pub fn identify_flag_types_for_task(
    course_config: CourseConfiguration,
    week_number: usize,
    task_id: String,
) {
    for week in course_config.weeks.iter() {
        if week.number == week_number {
            for task in week.tasks.iter() {
                if task.id == task_id {
                    if let Some(subtasks) = &task.subtasks {
                        for subtask in subtasks.iter() {
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
                if let Some(subtasks) = &task.subtasks {
                    for subtask in subtasks.iter() {
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
    for week in course_config.weeks.iter() {
        for task in week.tasks.iter() {
            if let Some(subtasks) = &task.subtasks {
                for subtask in subtasks.iter() {
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
