namespace com.yourorg.learningplatform

service LearningPlatformService {
    version: "1.0",
    operations: [
        NewUser,
        UserLogin,
        ListCourses,
        GetCourseConfig,
        GetCategory,
        GetTask,
        CompareAnswer
    ],
    errors: [Unauthorized, NotFound, InternalError]
}

operation NewUser{
    input: NewUserInput
    output: User,
}

structure NewUserInput {
    @required
    username: String,
    @required
    email: String,
    @required
    password: String,
}

structure User {
    id: Uuid,
    username: String,
    email: String,
}

operation UserLogin {
    input: UserLoginInput,
    output: UserLoginOutput,
    errors: [Unauthorized]
}

structure UserLoginInput {
    @required
    username: String,
    @required
    password: String,
}

structure UserLoginOutput {
    token: String,
    expiresAt: Timestamp,
}

operation ListCourses{

}

operation GetCourseConfig{
    input: CourseConfigInput,
    output: CourseConfigOutput
}

structure CourseConfigInput{
    @required
    course_id: Uuid,
}

structure CourseConfigOutput{}

operation GetCategory{
    input: Category
}

operation GetTask {
    input: TaskInput,
    output: TaskOutput,
    errors: [NotFound]
}
structure TaskInput{
    @required
    course_id: String,
    @required
    task_id: String,
    @required
    user_id: String,
}
// Needs to generate some kinda file for viewing the task and its parts like files
structure TaskOutput {
    task: WebTask
}

structure WebTask {
    id: String,
    title: String,
    description: String,
    category: String,
    files: list<String>, // for display/download
}
operation CompareAnswer{
    input: CheckAnswer
    output: CompareAnswerOutput
}

structure CheckAnswer{
    @required
    course_id: Uuid,
    @required
    task_id: String,
    @required
    user_id: Uuid,
    @required
    answer: String,
}


structure CompareAnswerOutput {
    correct: Boolean,
    feedback: String,
}

