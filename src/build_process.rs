use core::task;
use std::env;
use std::error::Error;
use std::process::Stdio;
use uuid::Uuid;

use crate::config::{CourseConfiguration, WeeksTasksBuild};
use crate::flag_generator;


struct EmbedFlag {

// id: id matches the task or subtask, which the embed flag is created for
// flag: The flag supposed to be embedded into the task or subtask
    id: String,
    flag: flag_generator::Flag,
}
struct EmbedFlags {

    embed_flags: Vec<EmbedFlag>
}

struct GenerationOutputs {
    output_files: Vec<String>,
    output_directory: String,

}

pub fn identify_flag_types_for_task(course_config: CourseConfiguration, week_number: usize, task_id: String) {
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

pub fn generate_embed_flags_for_task(course_config: CourseConfiguration, week_number: usize, task_id: String, uuid: Uuid) -> Result<EmbedFlags, Error> {
    identify_flag_types_for_task(course_config, week_number, task_id);
    let mut embed_flags = EmbedFlags {
        embed_flags: Vec::new(),
    };
    for week in course_config.weeks.iter() {
        if week.number == week_number {
            for task in week.tasks.iter() {
                if task.id == task_id {
                    if let Some(subtasks) = &task.subtasks {
                        for subtask in subtasks.iter() {
                            match_flag_types_and_generate_embed_flags(course_config, subtask.flag_type.flag_type, embed_flags, task_id, uuid);
                }
            }
        }
            else {
                for flag_config in task.flag_types.iter() {
                    match_flag_types_and_generate_embed_flags(course_config, flag_config.flag_type, embed_flags, task_id, uuid);
                    }
                }   
            }
        }
    }
    Ok(embed_flags)
}

pub fn generate_embed_flags_for_week(course_config: CourseConfiguration, week_number: usize, uuid: Uuid) -> Result<EmbedFlags, Error> {
    identify_flag_types_for_week(course_config, week_number);
    let mut embed_flags = EmbedFlags {
        embed_flags: Vec::new(),
    };
    for week in course_config.weeks.iter() {
        if week.number == week_number {
            for task in week.tasks.iter() {
                if let Some(subtasks) = &task.subtasks {
                    for subtask in subtasks.iter() {
                        match_flag_types_and_generate_embed_flags(course_config, subtask.flag_type.flag_type, embed_flags, subtask.id, uuid);
                    }
                }
                else {
                    for flag_config in task.flag_types.iter() {
                        match_flag_types_and_generate_embed_flags(course_config, flag_config.flag_type, embed_flags, task.id, uuid);
                    }
                }
            }
        }
    }
    Ok(embed_flags)
}

pub fn generate_embed_flags_for_all(course_config: CourseConfiguration, uuid: Uuid) -> Result<EmbedFlags, Error> {
    identify_all_flag_types(course_config);
    let mut embed_flags = EmbedFlags {
        embed_flags: Vec::new(),
    };
    for week in course_config.weeks.iter() {
        for task in week.tasks.iter() {
            if let Some(subtasks) = &task.subtasks {
                for subtask in subtasks.iter() {
                    match_flag_types_and_generate_embed_flags(course_config, subtask.flag_type.flag_type, embed_flags, subtask.id, uuid);
                }
            }
            else {
                for flag_config in task.flag_types.iter() {
                    match_flag_types_and_generate_embed_flags(course_config, flag_config.flag_type, embed_flags, task.id, uuid);
                }
            }
        }
    }
    Ok(embed_flags)
}

fn match_flag_types_and_generate_embed_flags(course_config: CourseConfiguration, flag_type: String, embed_flags: EmbedFlags, task_id: String, uuid: Uuid) {

    match &flag_type {
    "user_derived" => {
        //TODO: Check parameters
        let generated_flag = flag_generator::Flag::user_flag(task_id, course_config.flag_types.user_derived[0], course_config.flag_types.user_derived[1], task_id, uuid);
        let embed_flag = EmbedFlag {
            id: task_id,
            flag: generated_flag,
        };
        embed_flags.embed_flags.push(embed_flag);

    },
    "pure_random" => {
        //TODO: Check parameters
        let generated_flag = flag_generator::Flag::rng_flag(task_id, course_config.flag_types.pure_random);
        let embed_flag = EmbedFlag {
            id: task_id,
            flag: generated_flag,
        };
        embed_flags.embed_flags.push(embed_flag);
    },
    "rng_seed" => {
        //TODO: Check parameters
        let generated_flag = flag_generator::Flag::user_seed_flag(task_id, uuid);
        let embed_flag = EmbedFlag {
            id: task_id,
            flag: generated_flag,
        };
        embed_flags.embed_flags.push(embed_flag);
    },
    _ => {
        Err("Invalid flag type");
}
}
}

fn set_flags_to_env_variables(flags: EmbedFlags) {
    if flags.len() > 1 {
        for (i, flag) in flags.embed_flags.iter().enumerate() {
            let env_var = format!("FLAG_{}", i);
            std::env::set_var(env_var, flag.flag);
        }
    }
    std::env::set_var("FLAG", flags.embed_flags[0].flag);
}

fn get_build_info(course_config: CourseConfiguration, week_number: usize, task_id: String) -> WeeksTasksBuild {
    for week in course_config.weeks.iter() {
        if week.number == week_number {
            for task in week.tasks.iter() {
                if task.id == task_id {
                    task.build
                }
            }
        }
    }
}


pub fn build_task(course_config: CourseConfiguration, week_number: usize, task_id: String, uuid: Uuid)  {
    identify_flag_types_for_task(course_config, week_number, task_id);
    let flags = generate_embed_flags_for_task(course_config, week_number, task_id, uuid);
    //needs permissions to set env variables
    set_flags_to_env_variables(flags);
    let build_info = get_build_info(course_config, week_number, task_id);
    let resource_directory = build_info.directory;
    //points to scrip which builds the task
    let build_entrypoint = build_info.entrypoint;
    //let output_filename = build_info.output.name;

    env::set_current_dir(&resource_directory).expect("failed to locate resource directory");
    
    let output = std::process::Command::new("sh")
    .arg(build_entrypoint)
    .stdout(Stdio::inherit())
    .stderr(Stdio::inherit())
    .status()
    .expect("Failed to compile task");

}