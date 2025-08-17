use serde_json::Value;
use sqlx::PgPool;
use sqlx::types::Uuid;

pub struct CourseInput {
    pub id: Uuid,
    pub name: String,
    pub description: String,
}

pub struct CategoryInput {
    pub course_id: Uuid,
    pub name: String,
    pub number: i32,
}

pub struct TaskInput {
    pub id: String,
    pub course_id: Uuid,
    pub category_name: String,
    pub name: String,
    pub description: String,
    pub points: Option<i32>,
}

pub struct TaskStageInput {
    pub id: String,
    pub course_id: Uuid,
    pub category_name: String,
    pub task_id: String,
    pub name: String,
    pub description: String,
    pub weight: i32,
    pub flag: Value,
}

pub struct UserStageProgressInput {
    pub user_id: Uuid,
    pub course_id: Uuid,
    pub category_name: String,
    pub task_id: String,
    pub stage_id: String,
    pub completed: bool,
    pub score: Option<i32>,
}

pub async fn insert_course(pool: &PgPool, course: &CourseInput) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO courses(id, name, description) VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING"
    )
    .bind(course.id)
    .bind(&course.name)
    .bind(&course.description)
    .execute(pool)
    .await?;
    Ok(())
}

// Insert category
pub async fn insert_category(pool: &PgPool, category: &CategoryInput) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO categories(course_id, name, number) VALUES ($1, $2, $3) ON CONFLICT (course_id, name) DO NOTHING"
    )
    .bind(category.course_id)
    .bind(&category.name)
    .bind(category.number)
    .execute(pool)
    .await?;
    Ok(())
}

// Insert task
pub async fn insert_task(pool: &PgPool, task: &TaskInput) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO tasks(id, course_id, category_name, name, description, points)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (course_id, category_name, id) DO NOTHING",
    )
    .bind(&task.id)
    .bind(task.course_id)
    .bind(&task.category_name)
    .bind(&task.name)
    .bind(&task.description)
    .bind(task.points)
    .execute(pool)
    .await?;
    Ok(())
}

// Insert task stage
pub async fn insert_task_stage(pool: &PgPool, stage: &TaskStageInput) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO task_stages(id, course_id, category_name, task_id, name, description, weight, flag)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (course_id, category_name, task_id, id) DO NOTHING"
    )
    .bind(&stage.id)
    .bind(stage.course_id)
    .bind(&stage.category_name)
    .bind(&stage.task_id)
    .bind(&stage.name)
    .bind(&stage.description)
    .bind(stage.weight)
    .bind(&stage.flag)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn insert_user_stage_progress(
    pool: &PgPool,
    progress: &UserStageProgressInput,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO user_stage_progress(user_id, course_id, category_name, task_id, stage_id, completed, score)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (user_id, course_id, category_name, task_id, stage_id) DO NOTHING"
    )
    .bind(progress.user_id)
    .bind(progress.course_id)
    .bind(&progress.category_name)
    .bind(&progress.task_id)
    .bind(&progress.stage_id)
    .bind(progress.completed)
    .bind(progress.score)
    .execute(pool)
    .await?;
    Ok(())
}
