use crate::build_process::TaskBuildProcessOutput;
use crate::config::OutputKind;
use moodle_xml::{
    answer::Answer,
    question::{Question, QuestionType, ShortAnswerQuestion},
    quiz::Quiz,
};
use std::io::{self, BufRead, BufReader};

/// Create an exam from a list of task build process outputs, which includes the question as well
pub fn create_exam(
    items: Vec<TaskBuildProcessOutput>,
    category: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    println!("Creating exam");
    println!("{}", category);
    let mut questions: Vec<QuestionType> = Vec::with_capacity(items.len());

    for item in items {
        let instructions = item.get_readme();
        match instructions {
            Some(instructions) => {
                let file = std::fs::File::open(instructions.kind.get_filename()).unwrap();
                let reader = BufReader::new(file);
                let mut lines: Vec<String> = reader.lines().collect::<Result<_, _>>()?;
                lines.push("".to_string());
                lines.push("<br><br><b>Please, see the download links below. Exam questions are randomised and the link is different if you retry.</b>".to_string());
                lines.push("".to_string());
                lines.push("<ul>".to_string());
                for link in item.files {
                    if let (OutputKind::Resource(resource), Some(link)) = (link.kind, link.link) {
                        lines.push(format!(
                            "<li><a href=\"{}\">{}</a></li>",
                            link,
                            resource
                                .file_name()
                                .unwrap_or_default()
                                .to_ascii_lowercase()
                                .to_string_lossy(),
                        ));
                    }
                }
                lines.push("</ul>".to_string());
                let instructions_string = lines.join("\n");
                let mut question = ShortAnswerQuestion::new(
                    "This is a test".to_string(),
                    instructions_string,
                    None,
                );
                let answers = if item.flags.len() == 1 {
                    vec![Answer::new(
                        100,
                        item.flags[0].encase_flag(),
                        "Correct!".to_string().into(),
                    )]
                } else {
                    todo!("Multiple flags in subtasks not supported yet")
                };
                question
                    .add_answers(answers)
                    .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("Error: {:?}", e)))?;
                questions.push(question.into());
            }
            None => {
                println!("No instructions");
            }
        }
    }
    let mut quiz = Quiz::new(questions);
    let categories = vec![category.into()];
    quiz.set_categories(categories);
    quiz.to_xml("quiz.xml")
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("Error: {:?}", e)))?;
    Ok(())
}
