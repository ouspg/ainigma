begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(2);

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000004', true);
select extensions.is(
  (
    select count(*)::bigint
    from public.list_my_course_access_requests()
    where offering_key = 'test-course-a-local'
  ),
  1::bigint,
  'a learner can see their own access request'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
select extensions.is(
  (
    select count(*)::bigint
    from public.list_my_course_access_requests()
    where offering_key = 'test-course-a-local'
  ),
  0::bigint,
  'a different learner cannot see another learner’s access request'
);

select * from extensions.finish();
rollback;
