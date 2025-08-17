CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE courses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE categories (
    course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    number INTEGER NOT NULL,
    PRIMARY KEY (course_id, name)
);

CREATE TABLE tasks (
    id VARCHAR NOT NULL,                
    course_id UUID NOT NULL,
    category_name VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    description TEXT,
    points INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (course_id, category_name, id),
    FOREIGN KEY (course_id, category_name) REFERENCES categories(course_id, name) ON DELETE CASCADE
);

CREATE TABLE task_stages (
    id VARCHAR NOT NULL,                -- stage ID (e.g., "task001A")
    course_id UUID NOT NULL,
    category_name VARCHAR NOT NULL,
    task_id VARCHAR NOT NULL,           -- parent task ID
    name VARCHAR NOT NULL,
    description TEXT,
    weight INTEGER DEFAULT 1,
    flag JSONB,                         -- metadata like { kind: "user_derived" }
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (course_id, category_name, task_id, id),
    FOREIGN KEY (course_id, category_name, task_id) REFERENCES tasks(course_id, category_name, id) ON DELETE CASCADE
);


CREATE TABLE user_stage_progress (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id UUID NOT NULL,
    category_name VARCHAR NOT NULL,
    task_id VARCHAR NOT NULL,
    stage_id VARCHAR NOT NULL,           -- stage ID
    completed_at TIMESTAMPTZ,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    score INTEGER,
    PRIMARY KEY (user_id, course_id, category_name, task_id, stage_id),
    FOREIGN KEY (course_id, category_name, task_id, stage_id)
        REFERENCES task_stages(course_id, category_name, task_id, id)
        ON DELETE CASCADE
);