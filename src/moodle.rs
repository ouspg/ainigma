use crate::build_process::TaskBuildProcessOutput;
use crate::config::{OutputKind, Task};
use moodle_xml::{
    answer::Answer,
    question::{Question, QuestionType, ShortAnswerQuestion},
    quiz::Quiz,
};
use std::io::{self, BufRead, BufReader};

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

                lines.push("<br><br><b>Please, see the download links below. Exam questions are randomised and the link is different if you retry the exam.</b>".to_string());
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
                    todo!("Multiple flags in subtasks not supported yet")
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
