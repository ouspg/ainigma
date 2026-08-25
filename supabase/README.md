# Local Supabase

From the repository root:

```sh
./node_modules/.bin/supabase start
./node_modules/.bin/supabase db reset --local --yes  # after migration/seed changes
./node_modules/.bin/supabase test db --local
```

Stop it with `./node_modules/.bin/supabase stop`.
