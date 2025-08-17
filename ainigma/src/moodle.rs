use crate::build_process::TaskBuildContainer;
use crate::config::OutputKind;
use crate::flag_generator::Flag;
use itertools::Itertools;
use moodle_xml::{
    answer::Answer,
    question::{Question, QuestionType, ShortAnswerQuestion},
    quiz::Quiz,
};
use std::io::{self, BufRead, BufReader};

/// Create an exam from a list of task build process outputs, which includes the question as well
pub fn create_exam(
    items: TaskBuildContainer,
    category: &str,
    filename: &str,
    disable_upload: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut questions: Vec<QuestionType> = Vec::with_capacity(items.outputs.len());

    for item in items.outputs {
        // TODO batch not supported yet
        let instructions = item.get_readme();
        match instructions {
            Some(instructions) => {
                let file = std::fs::File::open(instructions.kind.get_filename()).unwrap();
                let reader = BufReader::new(file);
                let mut instructions: Vec<String> = reader.lines().collect::<Result<_, _>>()?;
                instructions.push("".to_string());

                if !disable_upload {
                    instructions.push("<br><br><b>Please, see the download links below. Exam questions are randomised and the links are different if you retry the exam.</b>".to_string());
                    instructions.push("<br>".to_string());
                    instructions.push(
                    "<div style=\"display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px;\">"
                        .to_string(),
                );
                    for link in &item.outputs {
                        if let (OutputKind::Resource(resource), Some(link)) =
                            (&link.kind, &link.link)
                        {
                            instructions.push(format!(
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
                    instructions.push("</div>".to_string());
                }

                let instructions_string = instructions.join("\n");
                let mut question =
                    ShortAnswerQuestion::new(items.task.name.clone(), instructions_string, None);
                let answers = if item.stage_flags.len() == 1 {
                    // Unknown flag, task build process has created this one
                    if let Flag::RngSeed(flag) = &item.stage_flags[0] {
                        vec![Answer::new(
                            100,
                            flag.value().to_string(),
                            "Correct!".to_string().into(),
                        )]
                    } else {
                        vec![
                            Answer::new(
                                100,
                                item.stage_flags[0].encased().to_string(),
                                "Correct!".to_string().into(),
                            ),
                            Answer::new(
                                100,
                                item.stage_flags[0].flag_string(),
                                "Correct!".to_string().into(),
                            ),
                        ]
                    }
                } else {
                    // Adds 1-inf flags as answer with chosen separator
                    process_multiple_flags(item.stage_flags.clone(), " ")
                };
                question
                    .add_answers(answers)
                    .map_err(|e| io::Error::other(format!("Error: {e:?}")))?;
                questions.push(question.into());
            }
            None => {
                panic!(
                    "No instructions provided for Moodle exam for unkown reason. Verify that you have `readme` type in output files."
                );
            }
        }
    }
    let mut quiz = Quiz::new(questions);
    let categories = vec![category.into()];
    quiz.set_categories(categories);
    quiz.to_xml(filename)
        .map_err(|e| io::Error::other(format!("Error: {e:?}")))?;
    Ok(())
}

// Function to encase each flag with a specified separator
fn encase_each_flag(flags: &[Flag], separator: &str) -> String {
    flags
        .iter()
        .map(|f| {
            if let Flag::RngSeed(flag) = f {
                flag.value().to_string()
            } else {
                f.encased().to_string()
            }
        })
        .join(separator)
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
                let points = ((r as f64 / total_flags as f64) * 100.0).round() as i8;

                answers.push(Answer::new(
                    points,
                    encased_combined_answer.clone(),
                    "Correct!".to_string().into(),
                ));
                answers.push(Answer::new(
                    points,
                    combined_answer.clone(),
                    "Correct!".to_string().into(),
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
        let mut flags2 = Vec::new();
        let mut flags3 = Vec::new();

        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let secret2 = "dslpl".to_string();
        let secret3 = "dslpl".to_string();
        let taskid = "task1".to_string();
        let taskid2 = "task2".to_string();
        let taskid3 = "task3".to_string();
        let taskid4 = "task4".to_string();
        let taskid5 = "task5".to_string();
        let taskid6 = "task6".to_string();
        let prefix4 = "task4_prefix".to_string();
        let prefix5 = "task5_prefix".to_string();
        let prefix6 = "task6_prefix".to_string();

        let flag1 = Flag::new_random_flag(taskid, 32);
        let flag2 = Flag::new_random_flag(taskid2, 32);
        let flag3 = Flag::new_random_flag(taskid3, 32);
        let flag4 = Flag::new_user_flag(prefix4, &Algorithm::HMAC_SHA3_256, &secret, &taskid4, &id);
        let flag5 =
            Flag::new_user_flag(prefix5, &Algorithm::HMAC_SHA3_256, &secret2, &taskid5, &id);
        let flag6 =
            Flag::new_user_flag(prefix6, &Algorithm::HMAC_SHA3_256, &secret3, &taskid6, &id);

        flags2.push(flag1);

        flags3.push(flag2);
        flags3.push(flag3);

        flags.push(flag4);
        flags.push(flag5);
        flags.push(flag6);

        let answers = process_multiple_flags(flags, " ");
        let answers2 = process_multiple_flags(flags2, " ");
        let answers3 = process_multiple_flags(flags3, " ");

        for answer in answers {
            match answer.fraction {
                33 => {
                    assert!(
                        answer.text.contains("task4_prefix:")
                            || answer.text.contains("task5_prefix:")
                            || answer.text.contains("task6_prefix:")
                    );
                }
                67 => {
                    assert!(
                        (answer.text.contains("task4_prefix:")
                            && answer.text.contains("task5_prefix:"))
                            || (answer.text.contains("task6_prefix:")
                                && answer.text.contains("task5_prefix:"))
                            || (answer.text.contains("task6_prefix:")
                                && answer.text.contains("task4_prefix:"))
                    );
                }
                100 => {
                    assert!(
                        (answer.text.contains("task4_prefix:")
                            && answer.text.contains("task5_prefix:")
                            && answer.text.contains("task6_prefix:"))
                    );
                }
                _ => {
                    unreachable!("Unexpected fraction value encountered in test")
                }
            }
        }
        for answer in answers2 {
            assert!(answer.fraction == 100);
            assert!(answer.text.contains("task1:"));
        }
        for answer in answers3 {
            match answer.fraction {
                50 => {
                    assert!(answer.text.contains("task2:") || answer.text.contains("task3:"));
                }
                100 => {
                    assert!(answer.text.contains("task2:") && answer.text.contains("task3:"));
                }
                _ => {
                    unreachable!("Unexpected fraction value encountered in test")
                }
            }
        }
    }
}
