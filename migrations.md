# Database Management

We are relying on [graphile-migrate](https://github.com/graphile/migrate) for PostgreSQL schema management.

This project uses **Yarn 4 with zero-install** - all dependencies are committed to the repository in `.yarn/cache`, so no `yarn install` is needed after cloning.

## Prerequisites

- [Node.js LTS](https://nodejs.org/en/)
- Run `corepack enable` once to enable Yarn

You should be ready to go!

## Graphile migrate


It's an opinionated SQL-powered productive roll-forward migration tool for PostgreSQL.
You read right, there are no rollback migration for each forward migration.


**If you need to revert some changes, create a new migration for it.**

## Configuration

Graphile configuration is stored in [.gmrc](./.gmrc) file. We can hook commands to specific actions if needed, like generating code once migration has been committed, ...

## Commands

The following env variables need to be defined while running command:
- NODE_TLS_REJECT_UNAUTHORIZED = '0' (mandatory for ppostgres12.cdbe.wurnet.nl)
- ROOT_DATABASE_URL (mandatory)
- DATABASE_URL (Development only. Not needed for prod.)
- SHADOW_DATABASE_URL (optional, development only. Not needed for prod.)

- **Development:**

`ROOT_DATABASE_URL=postgres://admin:admin@localhost:5432/postgres DATABASE_URL=postgres://admin:admin@localhost:5432/my_database SHADOW_DATABASE_URL=postgres://admin:admin@localhost:5432/local_shadow yarn run graphile-migrate [command] [args]`


For simplicity, set up an `.env` file (use .env vars carefully, avoid using this in prod) and use the short command:

`yarn gm [command] [args]`

This is configured as a script in [package.json](./package.json).

- **Production:**

`NODE_TLS_REJECT_UNAUTHORIZED = '0' DATABASE_URL=postgres://admin:admin@localhost:5432/my_database yarn run graphile-migrate [command] [args]`

### init

Should not be needed for current project, since it's already been initialised:

`yarn gm init`

### Initialize DB

You can run 

### migrate

**If you have created the DB manualy, this is probably the first command you need to run** It runs any un-executed committed migrations.
Obviously does NOT run the current working migration from current.sql. For use in production and development.

In production, most users only run graphile-migrate migrate which operates solely on the main database - there is no need for a shadow database in production.

`yarn gm migrate`

### watch

Runs any un-executed committed migrations and then runs and watches the current
migration from current.sql, re-running it on any change. For development purposes only.

`yarn gm watch`

### commit

Commits the current migration into the `committed/` folder, resetting the
current migration. Resets the shadow database.

```txt
Options:
  --help         Show help                                             [boolean]
  --message, -m  Optional commit message to label migration, must not contain
                 newlines.                                              [string]
```

`yarn gm commit --message "missing rls"`

Please always add a commit message, so that we can easily identify
what is done in the file from its name only.

### uncommit

This command is useful in development if you need to modify your latest commit
before you push/merge it, or if other DB commits have been made by other
developers and you need to 'rebase' your migration onto theirs. Moves the latest
commit out of the committed migrations folder and back to the current migration
(assuming the current migration is empty-ish). Removes the migration tracking
entry from **ONLY** the local database.

**Do not use after other databases have executed this committed migration otherwise they will fall out of sync.**

**Development only, and liable to cause conflicts with other developers - be careful.**

`yarn gm uncommit`

Assuming nothing else has changed, `yarn gm uncommit && yarn gm commit`
should result in the exact same hash.

### reset


Drops and re-creates the database, re-running all committed migrations from the
start. **HIGHLY DESTRUCTIVE**.

```txt
Options:
  --help    Show help                                                  [boolean]
  --shadow  Applies migrations to shadow DB.          [boolean] [default: false]
  --erase   This is your double opt-in to make it clear this DELETES EVERYTHING.
                                                      [boolean] [default: false]
```

`yarn gm reset --erase`


#### Initializing an empty Database with Graphile Migrate

You can initialize an empty DB automatically with Graphile Migrate by running the `reset` command.

### run

Compiles a SQL file, inserting all the placeholders, and then runs it against
the database. Useful for seeding. If called from an action will automatically
run against the same database (via GM_DBURL envvar) unless --shadow or
--rootDatabase are supplied.

```txt
Options:
  --help          Show help                                            [boolean]
  --shadow        Apply to the shadow database (for development).
                                                      [boolean] [default: false]
  --root          Run the file using the root user (but application database).
                                                      [boolean] [default: false]
  --rootDatabase  Like --root, but also runs against the root database rather
                  than application database.          [boolean] [default: false]
```

`yarn gm run migrations/setup/extensions.sql`

## Default commands

### Create a new local database

Define or replace `MY_DATABASE` and run:

`ROOT_DATABASE_URL=postgres://admin:admin@localhost:5432/postgres DATABASE_URL=postgres://admin:admin@localhost:5432/${MY_DATABASE} SHADOW_DATABASE_URL=postgres://admin:admin@localhost:5432/local_shadow yarn gm reset --erase`

### Reset database

You might need to kill pending connections to the database before:

```SQL
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE
  pg_stat_activity.datname = '${database}'
  AND pid <> pg_backend_pid();
```

Then run the same command as previous one:

`ROOT_DATABASE_URL=postgres://admin:admin@localhost:5432/postgres DATABASE_URL=postgres://admin:admin@localhost:5432/${MY_DATABASE} SHADOW_DATABASE_URL=postgres://admin:admin@localhost:5432/local_shadow yarn gm reset --erase`
