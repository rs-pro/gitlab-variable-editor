# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby CLI toolkit for managing GitLab projects. It includes tools for exporting/importing CI/CD variables and removing job artifacts.

## Architecture

**Single-file CLIs**: Both `gitlab_variable_editor` and `gitlab_artifact_remover` are standalone Thor-based scripts.

**Key dependencies**:
- `gitlab` gem (v4.19+) - GitLab API client
- `thor` gem (v1.3+) - CLI framework
- Standard library: `yaml`, `time`, `uri`

**Core flow (Variable Editor)**:
1. `GitLabVariableEditor` class inherits from `Thor`
2. Global options (`--endpoint`, `--token`, `--project`, `--group`) are defined as class options; `export`/`import` require exactly one of `--project (-p)` or `--group (-g)` (`require_target!`); `batch-update` always targets all projects
3. Three commands: `export`, `import`, and `batch-update`
4. Private method `configure_client` initializes the Gitlab client with user credentials
5. Target abstraction helpers: `target_type`/`target_id`/`target_label`, `fetch_variables` (project: `variables().auto_paginate`, group: `group_variables().auto_paginate`), `create_variable!`, `update_variable!`, `remove_variable!` dispatching to `create_variable`/`update_variable`/`remove_variable` or `create_group_variable`/`update_group_variable`/`remove_group_variable` gem methods

**Core flow (batch-update)**:
1. `batch_update(key, value = nil)` - when VALUE is omitted/empty, reads it from stdin (whole stream, one trailing newline stripped); confirmation then prompts on `/dev/tty` via `confirm_batch_update?`
2. Scans all projects from `client.projects(per_page: 100).auto_paginate`; per-project variable fetch failures are skipped with a warning
3. Matches variables by key + variable_type + environment_scope; updates via `update_variable(..., filter: { environment_scope: scope })`, creates via `create_variable` when `--set-missing`
4. With scope `*`, other-scope variables of same key/type are deleted via `remove_variable(..., filter: { environment_scope: s })` after a prominent warning
5. Scan phase rescues `Gitlab::Error::Error, SocketError, SystemCallError`; summary printed before yes/no confirmation

**Core flow (Artifact Remover)**:
1. `GitLabArtifactRemover` class inherits from `Thor`
2. Same global options as the variable editor
3. One command: `remove` with `--older-than` and `--force` options
4. Uses `auto_paginate` to iterate through all jobs
5. Filters jobs by checking `artifacts` array for `file_type == 'archive'`
6. Deletes artifacts via raw `client.delete` API call to `/projects/:id/jobs/:job_id/artifacts`

## Command Usage

**Install dependencies**:
```bash
bundle install
```

**Export variables** (command must come BEFORE options):
```bash
./gitlab_variable_editor export output.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project
```

**Import variables**:
```bash
./gitlab_variable_editor import input.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project
```

**Force import** (skip confirmation):
```bash
./gitlab_variable_editor import input.yml -e ... -t ... -p ... --force
```

**Batch update one variable across all projects** (VALUE read from stdin when omitted):
```bash
./gitlab_variable_editor batch-update SSH_KEY \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  --type env_var --scope '*' --set-missing --force < new-key.txt
```
Options: `--type env_var|file`, `-s/--scope` (default `*`; with `*` other-scope vars of same key/type are DELETED after warning), `-m/--set-missing` (create where absent), `-f/--force`.

**Remove artifacts older than 3 days**:
```bash
./gitlab_artifact_remover remove \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project \
  --older-than 3d
```

**Force artifact removal** (skip confirmation):
```bash
./gitlab_artifact_remover remove -e ... -t ... -p ... --older-than 3d --force
```

**Test commands**:
```bash
./gitlab_variable_editor help
./gitlab_variable_editor help export
./gitlab_variable_editor help import
./gitlab_artifact_remover help
./gitlab_artifact_remover help remove
```

## YAML Variable Structure

Variables are stored as an array of hashes with these keys:
- `key` - Variable name (required)
- `value` - Variable value (required)
- `variable_type` - `env_var` or `file` (default: `env_var`)
- `protected` - Boolean (default: false)
- `masked` - Boolean (default: false)
- `hidden` - Boolean (default: false, GitLab 17.4+)
- `raw` - Boolean (default: false)
- `environment_scope` - String (default: `*`)
- `description` - String (optional)

See `example-variables.yml` for a complete example.

## GitLab API Integration

**Authentication**: Uses `Gitlab.client()` with endpoint and private token.

**Key API methods** (from gitlab gem):
- `@client.variables(project_id)` - List all variables
- `@client.create_variable(project_id, key, value, options)` - Create variable
- `@client.update_variable(project_id, key, value, options)` - Update variable
- `@client.jobs(project_id, options)` - List jobs (with pagination)
- `@client.delete(path)` - Raw DELETE request (used for artifact removal)

**Artifact removal API endpoint**:
- `DELETE /projects/:id/jobs/:job_id/artifacts` - Delete artifacts for a specific job

**Error handling**: All GitLab API calls are wrapped in `begin/rescue` blocks catching `Gitlab::Error::Error`.

## Important Notes

- **Thor argument order**: Commands must come before options. Wrong: `./tool -e X export file`. Right: `./tool export file -e X`.
- **Sensitive data**: Exported YAML files contain secrets. The `.gitignore` excludes `*.yml` and `*.yaml` except `example-variables.yml`.
- **Token requirements**: GitLab personal access token needs `api` scope for full variable management and artifact removal.
- **User confirmation**: Import and artifact removal show a summary and require user input (`yes`/`y`) before proceeding, unless `--force` is used.
- **Artifact filtering**: The artifact remover checks for `file_type == 'archive'` in the job's `artifacts` array to distinguish real artifacts from job traces (logs).
