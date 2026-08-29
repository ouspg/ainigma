---
title: PostgreSQL schema organization notes
---

small database objects + boring source files + strong CI

On modern PostgreSQL, LANGUAGE SQL has a nicer SQL-standard body form:

```sql
CREATE FUNCTION ainigma.get_score(p_game_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
BEGIN ATOMIC
    SELECT g.score
      FROM ainigma.games AS g
     WHERE g.id = p_game_id;
END;
```

All errors on:

`SET plpgsql.extra_errors = 'all';`

Comment invariants and reasons, not syntax.

https://github.com/okbob/plpgsql_check

```
CREATE EXTENSION plpgsql_check;

SET plpgsql.extra_errors = 'all';

-- load schema
\ir db/install.sql
```
