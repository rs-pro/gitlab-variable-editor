# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby CLI tool for managing GitLab CI/CD variables. It allows exporting variables from a GitLab project to YAML files and importing them back, with user confirmation for overwrites.

## Architecture

**Single-file CLI**: `gitlab_variable_editor` is the entire application, built using Thor for command-line argument parsing.

**Key dependencies**:
- `gitlab` gem (v4.19+) - GitLab API client
- `thor` gem (v1.3+) - CLI framework
- Standard library: `yaml` for file operations

**Core flow**:
1. `GitLabVariableEditor` class inherits from `Thor`
2. Global options (`--endpoint`, `--token`, `--project`) are defined as class options
3. Two commands: `export` and `import`
4. Private method `configure_client` initializes the Gitlab client with user credentials

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

**Test commands**:
```bash
./gitlab_variable_editor help
./gitlab_variable_editor help export
./gitlab_variable_editor help import
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

**Error handling**: All GitLab API calls are wrapped in `begin/rescue` blocks catching `Gitlab::Error::Error`.

## Important Notes

- **Thor argument order**: Commands must come before options. Wrong: `./tool -e X export file`. Right: `./tool export file -e X`.
- **Sensitive data**: Exported YAML files contain secrets. The `.gitignore` excludes `*.yml` and `*.yaml` except `example-variables.yml`.
- **Token requirements**: GitLab personal access token needs `api` scope for full variable management.
- **User confirmation**: Import shows a diff summary and requires user input (`yes`/`y`) before overwriting, unless `--force` is used.
