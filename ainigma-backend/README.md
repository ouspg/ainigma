## Configuration

With the current implementation, Ainigma requires the following information.

- **TOML configuration file** — Contains core settings for Ainigma.
- **Task number (identifier)** — The specific task identifier.

Other things they need to take for backend to work

- **User ID** — When using the server backend, this should be provided dynamically; currently it is generated using `Uuid::now_v7()`.
- **Course secret**
- **Output_dir**- In the task folder with name "output"

## Software

Sqlx - Database
Smithy - Generating code for backend

## Serverside structure

/srv/ainigma/data/
/courses/  
 /<course_id>/ (or name)
config.toml (defined name for pathing)
/<category>/ (name)
/<task_id>/  
 entrypoint.sh  
 code_files...  
 /output/  
 /<student_uuid_v7>/  
 task files for student
resource_files/
Index file (index for quick course lookup and listing)

## workflow

[Client]
|
|-- Request (uuid, task_id, course_id) -->
|
[Server]
|-- Load course config
|-- Check if task exists for student (uuid, task_id, course_id)
| |-- Yes: return existing task
| |-- No:
| |-- Generate flags
| |-- Build task using course config
| |-- Save built task
|-- Return task data -->
|-- Add Correct flag / answer to database
[Client receives task and starts solving]
[Client]
|
|-- Does exercise
|
[Server]
|
|-- Check for correct answer -->
|-- Yes: send correct response and add progress
|-- No: send feedback
|
[Client] receives feedback

## Questions

- Category identifier?
- Course secret storage?
- Changes only when server down? or updates?

## Feedback

- No support for v7 uuid in postgre only v4
- New build function that takes a uuid, and just takes module and task_id
