# GitLab Variable Editor

A command-line toolkit for managing GitLab projects: export/import CI/CD variables and remove job artifacts.

## Features

- **Variable Export**: Download all CI/CD variables from a GitLab project to a YAML file
- **Variable Import**: Upload CI/CD variables from a YAML file to a GitLab project
- **Artifact Removal**: Delete job artifacts by age (e.g., older than 3 days)
- **Safety**: Prompts for confirmation before destructive operations
- **Complete**: Preserves all variable attributes (type, masked, protected, environment scope, etc.)

## Installation

1. Install dependencies:
```bash
bundle install
```

## Usage

### Export Variables

Export all CI/CD variables from a project to a YAML file:

```bash
./gitlab_variable_editor export OUTPUT_FILE \
  --endpoint https://gitlab.example.com/api/v4 \
  --token YOUR_ACCESS_TOKEN \
  --project my-group/my-project
```

**Example:**
```bash
./gitlab_variable_editor export production-vars.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project
```

### Import Variables

Import CI/CD variables from a YAML file to a project:

```bash
./gitlab_variable_editor import INPUT_FILE \
  --endpoint https://gitlab.example.com/api/v4 \
  --token YOUR_ACCESS_TOKEN \
  --project my-group/my-project
```

**Example:**
```bash
./gitlab_variable_editor import production-vars.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project
```

**Skip confirmation prompt with `--force`:**
```bash
./gitlab_variable_editor import production-vars.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project \
  --force
```

### Remove Job Artifacts

Remove job artifacts older than a specified duration:

```bash
./gitlab_artifact_remover remove \
  --endpoint https://gitlab.example.com/api/v4 \
  --token YOUR_ACCESS_TOKEN \
  --project my-group/my-project \
  --older-than 3d
```

**Example:**
```bash
./gitlab_artifact_remover remove \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project \
  --older-than 3d
```

**Supported duration formats:** `3d` (days), `1w` (weeks), `24h` (hours), `30m` (minutes).

**Skip confirmation prompt with `--force`:**
```bash
./gitlab_artifact_remover remove \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-group/my-project \
  --older-than 3d \
  --force
```

## Options

### Global Options (Required for all commands)

- `-e, --endpoint` - GitLab API endpoint (e.g., `https://gitlab.example.com/api/v4`)
- `-t, --token` - GitLab personal access token
- `-p, --project` - Project ID or path (e.g., `my-group/my-project` or `42`)

### Import-Specific Options

- `-f, --force` - Skip confirmation prompts when overwriting variables

### Artifact Remover-Specific Options

- `-o, --older-than` - Only remove artifacts older than this duration (e.g., `3d`, `1w`, `24h`, `30m`). Without this flag, **all** artifacts are targeted.
- `-f, --force` - Skip confirmation prompt before deleting artifacts

## YAML Format

The exported YAML file contains an array of variables with the following structure:

```yaml
- key: VARIABLE_NAME
  value: variable_value
  variable_type: env_var  # or 'file'
  protected: false
  masked: true
  hidden: false
  raw: false
  environment_scope: '*'
  description: Optional description
```

### Variable Attributes

- **key**: Variable name (A-Z, a-z, 0-9, underscore only, max 255 chars)
- **value**: Variable value
- **variable_type**: `env_var` (default) or `file`
- **protected**: If true, variable only available on protected branches/tags
- **masked**: If true, variable value is masked in job logs
- **hidden**: If true, variable is hidden (GitLab 17.4+)
- **raw**: If true, variable expansion is disabled
- **environment_scope**: Scope where variable is available (default: `*`)
- **description**: Optional description of the variable

## Access Token Permissions

Your GitLab access token needs the following scopes:

- `api` - Full API access (required for reading and writing CI/CD variables, and for deleting job artifacts)

To create a personal access token:
1. Go to GitLab → User Settings → Access Tokens
2. Enter a name and expiration date
3. Select the `api` scope
4. Click "Create personal access token"

## Examples

### Backup variables from production

```bash
./gitlab_variable_editor export prod-backup.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-org/production-app
```

### Copy variables from one project to another

```bash
# Export from source project
./gitlab_variable_editor export vars.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-org/source-project

# Import to destination project
./gitlab_variable_editor import vars.yml \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-org/destination-project
```

### Manually edit exported variables

```bash
# Export variables
./gitlab_variable_editor export vars.yml -e ... -t ... -p ...

# Edit the YAML file with your preferred editor
vim vars.yml

# Import the modified variables
./gitlab_variable_editor import vars.yml -e ... -t ... -p ...
```

### Clean up old job artifacts

```bash
# Remove artifacts older than 3 days (requires confirmation)
./gitlab_artifact_remover remove \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-org/production-app \
  --older-than 3d

# Remove all artifacts without confirmation (use with caution)
./gitlab_artifact_remover remove \
  -e https://gitlab.example.com/api/v4 \
  -t glpat-xxxxxxxxxxxxxxxxxxxx \
  -p my-org/production-app \
  --force
```

## Error Handling

The tool provides clear error messages for common issues:

- Invalid credentials or endpoint
- Project not found or insufficient permissions
- Invalid YAML format
- API errors (duplicate keys, invalid values, etc.)

## Acknowledgments

The artifact removal feature was inspired by the bash script written by [Chris Arceneaux](https://github.com/carceneaux):
- Gist: https://gist.github.com/carceneaux/b75d483e3e0cb798ae60c424300d5a0b

## License

MIT License
