use core::str;
use std::collections::HashMap;
use uuid::Uuid;

use crate::config::{BuildConfig, CourseConfiguration, Task};
use crate::flag_generator::{self};

/*
struct GenerationOutputs {
    output_files: Vec<String>,
    output_directory: String,

}
*/

fn create_flag_id_pairs_by_task<'a>(
    task_config: &'a Task,
    course_config: &'a CourseConfiguration,
    uuid: Uuid,
) -> HashMap<String, String> {
    let mut flags = HashMap::with_capacity(3);
    for stage in &task_config.stages {
        // let task_id = part.id.clone();
        let id: &str;
        if let Some(stage_id) = &stage.id {
            id = stage_id;
        } else {
            id = &task_config.id
        }
        match stage.flag.kind.as_str() {
            "user_derived" => {
                let flag_value = flag_generator::Flag::user_flag(
                    id.into(),
                    course_config.flag_types.user_derived.algorithm.clone(),
                    course_config.flag_types.user_derived.secret.clone(),
                    id.into(),
                    uuid,
                )
                .flag_string();
                let flag_key = format!("FLAG_USER_DERIVED_{}", id);
                flags.insert(flag_key, flag_value);
            }
            "pure_random" => {
                let flag_value = flag_generator::Flag::random_flag(
                    id.into(),
                    course_config.flag_types.pure_random.length,
                )
                .flag_string();
                let flag_key = format!("FLAG_PURE_RANDOM_{}", id);
                flags.insert(flag_key, flag_value);
            }
            "rng_seed" => {
                let flag_value = flag_generator::Flag::user_seed_flag(
                    id.into(),
                    course_config.flag_types.user_derived.algorithm.clone(),
                    course_config.flag_types.user_derived.secret.clone(),
                    id.into(),
                    uuid,
                )
                .flag_string();
                let flag_key = format!("FLAG_USER_SEED_{}", id);
                flags.insert(flag_key, flag_value);
            }
            _ => panic!("Invalid flag type"),
        };
    }
    flags
}

#[allow(dead_code)]
fn get_build_info(
    course_config: &mut CourseConfiguration,
    //week_number: u8, needed?
    task_id: String,
) -> Result<BuildConfig, String> {
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
    course_config: &CourseConfiguration,
    //week_number: u8,
    task_id: String,
    uuid: Uuid,
) {
    let task_config = course_config
        .get_task_by_id(&task_id)
        .unwrap_or_else(|| panic!("Task with id {} not found in course configuration", task_id));
    let id_flag_pairs = create_flag_id_pairs_by_task(task_config, course_config, uuid);

    //env::set_current_dir(&task_config.build.directory)
    //    .expect("failed to locate resource directory");

    let output = std::process::Command::new("sh")
        .arg(task_config.build.entrypoint.clone())
        .envs(id_flag_pairs)
        .current_dir(&task_config.build.directory)
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
}
