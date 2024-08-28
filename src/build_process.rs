use core::str;
use std::env;
use uuid::Uuid;

use crate::config::{CourseConfiguration, FlagConfig, WeeksTasksBuild};
use crate::flag_generator;

#[derive(Clone)]
#[allow(dead_code)]
pub struct EmbedFlag {
    // id: id matches the task or subtask, which the embed flag is created for (unused at the moment)
    // flag: The flag supposed to be embedded into the task
    id: String,
    flag: flag_generator::Flag,
}
#[derive(Clone)]
pub struct EmbedFlags {
    embed_flags: Vec<EmbedFlag>,
}
/*
struct GenerationOutputs {
    output_files: Vec<String>,
    output_directory: String,

}
*/

fn find_flagtype_for_task(
    course_config: CourseConfiguration,
    task_id: String,
) -> Result<Vec<FlagConfig>, String> {
    for week in course_config.weeks {
        for task in week.tasks {
            if task_id == task.id {
                return Ok(task.flag_types.clone());
            }
        }
    }
    Err("Flagtype not found!".to_string())
}

pub fn generate_embed_flags_for_task(
    course_config: &mut CourseConfiguration,
    task_id: String,
    uuid: Uuid,
) -> EmbedFlags {
    let flag_type = find_flagtype_for_task(course_config.clone(), task_id.clone()).unwrap();
    let mut embed_flags = EmbedFlags {
        embed_flags: Vec::new(),
    };

    match_flag_types_and_generate_embed_flags(
        course_config,
        flag_type.clone(),
        &mut embed_flags,
        uuid,
    );

    embed_flags
}

fn match_flag_types_and_generate_embed_flags(
    course_config: &mut CourseConfiguration,
    flag_types: Vec<FlagConfig>,
    embed_flags: &mut EmbedFlags,
    uuid: Uuid,
) {
    for flag_type in flag_types {
        match flag_type.flag_type.as_str() {
            "user_derived" => {
                let generated_flag = flag_generator::Flag::user_flag(
                    flag_type.id.clone(),
                    course_config.flag_types.user_derived.algorithm.clone(),
                    course_config.flag_types.user_derived.secret.clone(),
                    flag_type.id.clone(),
                    uuid,
                );
                let embed_flag = EmbedFlag {
                    id: flag_type.id.clone(),
                    flag: generated_flag,
                };
                embed_flags.embed_flags.push(embed_flag);
            }
            "pure_random" => {
                let generated_flag = flag_generator::Flag::random_flag(
                    flag_type.id.clone(),
                    course_config.flag_types.pure_random.length,
                );
                let embed_flag = EmbedFlag {
                    id: flag_type.id.clone(),
                    flag: generated_flag,
                };
                embed_flags.embed_flags.push(embed_flag);
            }
            "rng_seed" => {
                let generated_flag =
                    flag_generator::Flag::user_seed_flag(flag_type.id.clone(), uuid);
                let embed_flag = EmbedFlag {
                    id: flag_type.id.clone(),
                    flag: generated_flag,
                };
                embed_flags.embed_flags.push(embed_flag);
            }
            _ => {
                panic!("Invalid flag type");
            }
        }
    }
}

fn set_flags_to_env_variables(flags: &mut EmbedFlags) {
    if flags.embed_flags.len() > 1 {
        for (i, flag) in flags.embed_flags.iter_mut().enumerate() {
            let env_var_flag = flag_generator::Flag::flag_string(&mut flag.flag);
            let env_var_name = format!("FLAG_{}", i + 1);
            std::env::set_var(env_var_name, env_var_flag);
        }
    }
    let mut flag = flags.embed_flags[0].flag.clone();
    let env_var_flag = flag_generator::Flag::flag_string(&mut flag);
    std::env::set_var("FLAG", env_var_flag);
}

fn get_build_info(
    course_config: &mut CourseConfiguration,
    //week_number: u8, needed?
    task_id: String,
) -> Result<WeeksTasksBuild, String> {
    for week in &mut course_config.weeks {
        for task in &week.tasks {
            if task_id == task.id {
                return Ok(task.build.clone());
            }
        }
    }
    Err(format!(
        "Build information for task with id {} not found!",
        task_id
    ))
}

pub fn build_task(
    course_config: &mut CourseConfiguration,
    //week_number: u8,
    task_id: String,
    uuid: Uuid,
) {
    let mut flags = generate_embed_flags_for_task(course_config, task_id.clone(), uuid);
    set_flags_to_env_variables(&mut flags);
    let build_info = get_build_info(course_config, task_id).unwrap();
    let resource_directory = build_info.directory;
    //the script which builds the task
    let build_entrypoint = build_info.entrypoint;
    //let output_filename = build_info.output.name;

    env::set_current_dir(&resource_directory).expect("failed to locate resource directory");

    let output = std::process::Command::new("sh")
        .arg(build_entrypoint)
        .output()
        .expect("Failed to compile task");

    if output.status.success() {
        let stdout = str::from_utf8(&output.stdout).expect("Failed to parse output");
        let mut lines = stdout.lines();

        let path = lines.next().unwrap_or_default();
        println!("Absolute path of the created files: {} ", path);
    }
    if !output.status.success() {
        eprintln!("Error: {}", str::from_utf8(&output.stderr).unwrap());
    }

    flags.embed_flags.clear();
}
