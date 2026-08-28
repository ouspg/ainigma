alter table "private"."github_course_access"
  drop constraint "github_course_access_access_request_id_fkey";

alter table "private"."course_access_requests"
  add constraint "course_access_requests_id_course_profile_unique" unique (id, course_id, requester_profile_id);

alter table "private"."github_course_access"
  add constraint "github_course_access_request_course_profile_fk" foreign key (access_request_id, course_id, profile_id)
    references private.course_access_requests(id, course_id, requester_profile_id) on delete restrict;
