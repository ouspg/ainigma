use crate::build_process::TaskBuildProcessOutput;
use crate::config::{OutputKind, Task};
use moodle_xml::{
    answer::Answer,
    question::{Question, QuestionType, ShortAnswerQuestion},
    quiz::Quiz,
};
use std::io::{self, BufRead, BufReader};
use itertools::Itertools;
use crate::flag_generator::Flag;

/// Create an exam from a list of task build process outputs, which includes the question as well
pub fn create_exam(
    task_config: &Task,
    items: Vec<TaskBuildProcessOutput>,
    category: &str,
    filename: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut questions: Vec<QuestionType> = Vec::with_capacity(items.len());

    for item in items {
        let instructions = item.get_readme();
        match instructions {
            Some(instructions) => {
                let file = std::fs::File::open(instructions.kind.get_filename()).unwrap();
                let reader = BufReader::new(file);
                let mut lines: Vec<String> = reader.lines().collect::<Result<_, _>>()?;
                lines.push("".to_string());

                lines.push("<br><br><b>Please, see the download links below. Exam questions are randomised and the links are different if you retry the exam.</b>".to_string());
                lines.push("<br>".to_string());
                lines.push(
                    "<div style=\"display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px;\">"
                        .to_string(),
                );
                for link in item.files {
                    if let (OutputKind::Resource(resource), Some(link)) = (link.kind, link.link) {
                        lines.push(format!(
                            "<a href=\"{}\" target=\"_blank\" class=\"btn btn-primary\">{}</a>",
                            link,
                            resource
                                .file_name()
                                .unwrap_or_default()
                                .to_ascii_lowercase()
                                .to_string_lossy(),
                        ));
                    }
                }
                lines.push("</div>".to_string());

                let instructions_string = lines.join("\n");
                let mut question =
                    ShortAnswerQuestion::new(task_config.name.clone(), instructions_string, None);
                let answers = if item.flags.len() == 1 {
                    vec![
                        Answer::new(
                            100,
                            item.flags[0].encase_flag(),
                            "Correct!".to_string().into(),
                        ),
                        Answer::new(
                            100,
                            item.flags[0].flag_string(),
                            "Correct!".to_string().into(),
                        ),
                    ] 
                } else {
                    // Adds 1-inf flags as answer with chosen separator
                    process_multiple_flags(item.flags.clone(), ";")
                };
                question
                    .add_answers(answers)
                    .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("Error: {:?}", e)))?;
                questions.push(question.into());
            }
            None => {
                panic!("No instructions provided for Moodle exam for unkown reason. Verify that you have `readme` type in output files.");
            }
        }
    }
    let mut quiz = Quiz::new(questions);
    let categories = vec![category.into()];
    quiz.set_categories(categories);
    quiz.to_xml(filename)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("Error: {:?}", e)))?;
    Ok(())
}

// Function to encase each flag with a specified separator
fn encase_each_flag(flags: &[Flag], separator: &str) -> String {
    flags.iter().map(|f| f.encase_flag()).join(separator)
}

// Function to join flags without encasing them
fn join_flags(flags: &[Flag], separator: &str) -> String {
    flags.iter().map(|f| f.flag_string()).join(separator)
}

// Function to process multiple flags and create answers
fn process_multiple_flags(flags: Vec<Flag>, separator: &str) -> Vec<Answer> {
    let total_flags = flags.len();
    let mut answers = Vec::new();

    for r in 1..=total_flags {
        for combination in flags.iter().combinations(r) {
            for perm in combination.iter().permutations(r) {
                let perm_flags: Vec<Flag> = 
                    perm.iter().cloned().map(|&flag| flag.clone()).collect();
                let encased_combined_answer = encase_each_flag(&perm_flags, separator); // Pass as a slice
                let combined_answer = join_flags(&perm_flags, separator); // Pass as a slice

                // Calculate points based on the number of flags
                let points = ((r as f64 / total_flags as f64) * 100.0).round() as u8;

                answers.push(Answer::new(
                    points,
                    encased_combined_answer.clone(),
                    "Correct!".to_string().into()
                ));
                answers.push(Answer::new(
                    points,
                    combined_answer.clone(),
                    "Correct!".to_string().into()
                ));
            }
        }
    }
    
    answers
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::flag_generator::Algorithm;
    use uuid::Uuid;

    #[test]
    fn test_multiple_flags() {
        let mut flags = Vec::new();

        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let secret2 = "dslpl".to_string();
        let secret3 = "dslpl".to_string();
        let taskid = "task1".to_string();
        let taskid2 = "Wording mording".to_string();
        let taskid3 = "kdosogkdo".to_string();
        let prefix = "task_prefix".to_string();

        let flag1 = Flag::new_random_flag(taskid2, 32);
        let flag2 = Flag::new_user_flag(taskid, &Algorithm::HMAC_SHA3_256, &secret, &secret3, &id);
        let flag3 = Flag::new_user_flag(prefix, &Algorithm::HMAC_SHA3_256, &secret2, &taskid3, &id);

        flags.push(flag1);
        flags.push(flag2);
        flags.push(flag3);

        let answers = process_multiple_flags(flags, ";");
        for answer in answers {
            println!("{:?}", answer);
        }
    }
}