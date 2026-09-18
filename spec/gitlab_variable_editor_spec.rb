# frozen_string_literal: true

require 'tempfile'
require 'ostruct'
require 'yaml'

load File.expand_path('../../gitlab_variable_editor', __FILE__)

RSpec.describe GitLabVariableEditor do
  let(:temp_yaml_file) { Tempfile.new(['import', '.yml']) }

  after do
    temp_yaml_file.close
    temp_yaml_file.unlink
  end

  def write_yaml_file(variables)
    temp_yaml_file.write(YAML.dump(variables))
    temp_yaml_file.rewind
  end

  def create_mock_client(variables)
    client = Object.new
    client.define_singleton_method(:variables) { |*_args| paginated_array(variables) }
    client.define_singleton_method(:update_variable) { |*_args| }
    client.define_singleton_method(:create_variable) { |*_args| }
    client.define_singleton_method(:remove_variable) do |*_args|
      @deleted ||= []
      @deleted << _args[1]
    end
    client.instance_variable_set(:@deleted, [])
    client
  end

  def create_group_mock_client(variables)
    client = Object.new
    client.define_singleton_method(:group_variables) { |*_args| paginated_array(variables) }
    %i[create_group_variable update_group_variable remove_group_variable].each do |name|
      client.define_singleton_method(name) do |*args|
        instance_variable_set("@#{name}", []) unless instance_variable_get("@#{name}")
        instance_variable_get("@#{name}") << args
      end
    end
    client
  end

  def create_editor_for_test(opts)
    editor = GitLabVariableEditor.allocate
    editor.instance_variable_set(:@options, opts)
    editor
  end

  describe 'import command with --delete-other flag' do
    context 'when there are no variables to delete' do
      it 'does not show delete confirmation when no vars to delete' do
        existing_vars = [
          OpenStruct.new(key: 'EXISTING_VAR', value: 'value1'),
          OpenStruct.new(key: 'ANOTHER_VAR', value: 'value2')
        ]
        mock_client = create_mock_client(existing_vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)

        write_yaml_file([
          { 'key' => 'EXISTING_VAR', 'value' => 'updated1' },
          { 'key' => 'NEW_VAR', 'value' => 'newvalue' }
        ])

        opts = {
          force: true,
          'delete-other': true,
          endpoint: 'https://example.com',
          token: 'x',
          project: 'p'
        }
        editor = create_editor_for_test(opts)

        output = capture_stdout { editor.import(temp_yaml_file.path) }
        expect(output).not_to match(/will be DELETED/)
      end
    end

    context 'when there are variables to delete' do
      it 'shows confirmation with list of variables to delete when --delete-other is used without --force' do
        existing_vars = [
          OpenStruct.new(key: 'TO_DELETE_1', value: 'delete1'),
          OpenStruct.new(key: 'TO_DELETE_2', value: 'delete2'),
          OpenStruct.new(key: 'TO_KEEP', value: 'keep')
        ]
        mock_client = create_mock_client(existing_vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)

        write_yaml_file([{ 'key' => 'TO_KEEP', 'value' => 'keep' }])

        opts = {
          'delete-other': true,
          endpoint: 'https://example.com',
          token: 'x',
          project: 'p'
        }
        editor = create_editor_for_test(opts)

        allow(STDIN).to receive(:gets).and_return('yes')
        output = capture_stdout { editor.import(temp_yaml_file.path) }
        expect(output).to include('TO_DELETE_1')
        expect(output).to include('TO_DELETE_2')
      end

      it 'deletes variables when --delete-other is used with --force' do
        existing_vars = [
          OpenStruct.new(key: 'TO_DELETE_1', value: 'delete1'),
          OpenStruct.new(key: 'TO_DELETE_2', value: 'delete2'),
          OpenStruct.new(key: 'TO_KEEP', value: 'keep')
        ]
        mock_client = create_mock_client(existing_vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)

        write_yaml_file([{ 'key' => 'TO_KEEP', 'value' => 'keep' }])

        opts = {
          force: true,
          'delete-other': true,
          endpoint: 'https://example.com',
          token: 'x',
          project: 'p'
        }
        editor = create_editor_for_test(opts)

        capture_stdout { editor.import(temp_yaml_file.path) }

        expect(mock_client.instance_variable_get(:@deleted)).to contain_exactly('TO_DELETE_1', 'TO_DELETE_2')
      end

      it 'does not delete variables when --delete-other is not specified' do
        existing_vars = [
          OpenStruct.new(key: 'TO_DELETE_1', value: 'delete1'),
          OpenStruct.new(key: 'TO_KEEP', value: 'keep')
        ]
        mock_client = create_mock_client(existing_vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)

        write_yaml_file([{ 'key' => 'TO_KEEP', 'value' => 'keep' }])

        opts = {
          force: true,
          endpoint: 'https://example.com',
          token: 'x',
          project: 'p'
        }
        editor = create_editor_for_test(opts)

        capture_stdout { editor.import(temp_yaml_file.path) }

        expect(mock_client.instance_variable_get(:@deleted)).to be_empty
      end
    end

    context 'deletion confirmation flow' do
      it 'cancels when user types no at delete confirmation' do
        existing_vars = [
          OpenStruct.new(key: 'VAR_TO_DELETE', value: 'value'),
          OpenStruct.new(key: 'VAR_TO_KEEP', value: 'keep')
        ]
        mock_client = create_mock_client(existing_vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)

        write_yaml_file([{ 'key' => 'VAR_TO_KEEP', 'value' => 'keep' }])

        opts = {
          'delete-other': true,
          endpoint: 'https://example.com',
          token: 'x',
          project: 'p'
        }
        editor = create_editor_for_test(opts)

        allow(STDIN).to receive(:gets).and_return('no')

        output = capture_stdout do
          begin
            editor.import(temp_yaml_file.path)
          rescue SystemExit
            # expected: command exits after cancellation
          end
        end
        expect(output).to include('Import cancelled')
        expect(mock_client.instance_variable_get(:@deleted)).to be_empty
      end
    end

    context 'summary output' do
      it 'shows variables to delete in summary' do
        existing_vars = [
          OpenStruct.new(key: 'EXISTING', value: 'val1'),
          OpenStruct.new(key: 'TO_DELETE', value: 'val2')
        ]
        mock_client = create_mock_client(existing_vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)

        write_yaml_file([{ 'key' => 'EXISTING', 'value' => 'updated' }])

        opts = {
          force: true,
          'delete-other': true,
          endpoint: 'https://example.com',
          token: 'x',
          project: 'p'
        }
        editor = create_editor_for_test(opts)

        output = capture_stdout { editor.import(temp_yaml_file.path) }
        expect(output).to include('Variables to delete: 1')
      end
    end
  end
  describe 'import command with --group' do
    let(:group_opts) do
      {
        force: true,
        endpoint: 'https://example.com',
        token: 'x',
        project: nil,
        group: 'krasichka'
      }
    end

    it 'fetches, creates and updates via the group variable API methods' do
      mock_client = create_group_mock_client([OpenStruct.new(key: 'TO_KEEP', value: 'keep')])
      allow(Gitlab).to receive(:client).and_return(mock_client)

      write_yaml_file([
        { 'key' => 'TO_KEEP', 'value' => 'updated' },
        { 'key' => 'NEW_GROUP_VAR', 'value' => 'v' }
      ])

      editor = create_editor_for_test(group_opts)
      capture_stdout { editor.import(temp_yaml_file.path) }

      expect(mock_client.instance_variable_get(:@create_group_variable)).to contain_exactly(
        ['krasichka', 'NEW_GROUP_VAR', 'v', anything]
      )
      expect(mock_client.instance_variable_get(:@update_group_variable)).to contain_exactly(
        ['krasichka', 'TO_KEEP', 'updated', anything]
      )
      expect(mock_client.instance_variable_get(:@remove_group_variable)).to be_nil
    end

    it 'deletes other variables via the group API with --delete-other' do
      opts = group_opts.merge('delete-other': true)
      mock_client = create_group_mock_client([
        OpenStruct.new(key: 'TO_KEEP', value: 'keep'),
        OpenStruct.new(key: 'TO_DELETE', value: 'x')
      ])
      allow(Gitlab).to receive(:client).and_return(mock_client)

      write_yaml_file([{ 'key' => 'TO_KEEP', 'value' => 'keep' }])

      editor = create_editor_for_test(opts)
      capture_stdout { editor.import(temp_yaml_file.path) }

      expect(mock_client.instance_variable_get(:@remove_group_variable)).to contain_exactly(
        ['krasichka', 'TO_DELETE']
      )
    end
  end

  describe 'target validation' do
    def run_import_with(opts)
      mock_client = create_mock_client([])
      allow(Gitlab).to receive(:client).and_return(mock_client)
      write_yaml_file([{ 'key' => 'K', 'value' => 'v' }])

      editor = create_editor_for_test(opts)
      output = capture_stdout do
        begin
          editor.import(temp_yaml_file.path)
        rescue SystemExit
          # expected: command exits on invalid target options
        end
      end
      output
    end

    it 'exits when both --project and --group are given' do
      opts = {
        force: true,
        endpoint: 'https://example.com',
        token: 'x',
        project: 'p',
        group: 'g'
      }

      output = run_import_with(opts)
      expect(output).to include('exactly one')
    end

    it 'exits when neither --project nor --group is given' do
      opts = {
        force: true,
        endpoint: 'https://example.com',
        token: 'x',
        project: nil,
        group: nil
      }

      output = run_import_with(opts)
      expect(output).to include('exactly one')
    end
  end

  describe 'batch_update command' do
    def create_project(id, path)
      OpenStruct.new(id: id, path_with_namespace: path)
    end

    def create_var(key, type: 'env_var', scope: '*')
      OpenStruct.new(key: key, variable_type: type, environment_scope: scope)
    end

    def create_batch_client(projects, vars_by_project)
      paginated = Object.new
      paginated.define_singleton_method(:auto_paginate) do |&block|
        block ? projects.each(&block) : projects
      end

      client = Object.new
      client.define_singleton_method(:projects) { |*_args| paginated }
      client.define_singleton_method(:variables) { |project_id| paginated_array(vars_by_project.fetch(project_id, [])) }

      %i[update_variable create_variable remove_variable].each do |name|
        client.define_singleton_method(name) do |*args|
          instance_variable_set("@#{name}", []) unless instance_variable_get("@#{name}")
          instance_variable_get("@#{name}") << args
        end
      end
      client
    end

    let(:batch_opts) do
      {
        endpoint: 'https://example.com',
        token: 'x',
        project: nil,
        type: 'env_var',
        scope: '*',
        'set-missing': false,
        force: true
      }
    end

    it 'updates the variable only where it exists when set-missing is off' do
      projects = [create_project(1, 'group/one'), create_project(2, 'group/two')]
      vars = { 1 => [create_var('SSH_KEY')], 2 => [] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)

      editor = create_editor_for_test(batch_opts)
      output = capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }

      expect(mock_client.instance_variable_get(:@update_variable).size).to eq(1)
      expect(mock_client.instance_variable_get(:@update_variable).first).to eq(
        [1, 'SSH_KEY', 'new-secret', { filter: { environment_scope: '*' } }]
      )
      expect(mock_client.instance_variable_get(:@create_variable)).to be_nil
      expect(output).to include('Projects skipped (variable missing): 1')
      expect(output).to include('Scope: * (default)')
    end

    it 'creates missing variables with --set-missing' do
      opts = batch_opts.merge('set-missing': true)
      projects = [create_project(1, 'group/one'), create_project(2, 'group/two')]
      vars = { 1 => [create_var('SSH_KEY')], 2 => [] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)

      editor = create_editor_for_test(opts)
      capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }

      expect(mock_client.instance_variable_get(:@create_variable)).to contain_exactly(
        [2, 'SSH_KEY', 'new-secret', { variable_type: 'env_var', environment_scope: '*' }]
      )
    end

    it 'matches variables by kind and does not touch other kinds' do
      opts = batch_opts.merge(type: 'file')
      projects = [create_project(1, 'group/one')]
      vars = { 1 => [create_var('SSH_KEY', type: 'env_var')] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)

      editor = create_editor_for_test(opts)
      capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }

      expect(mock_client.instance_variable_get(:@update_variable)).to be_nil
    end

    it 'deletes other-scope variables when scope is "*"' do
      projects = [create_project(1, 'group/one')]
      vars = { 1 => [create_var('SSH_KEY'), create_var('SSH_KEY', scope: 'prod'), create_var('SSH_KEY', scope: 'staging'), create_var('OTHER', scope: 'prod')] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)

      editor = create_editor_for_test(batch_opts)
      output = capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }

      expect(mock_client.instance_variable_get(:@update_variable)).to contain_exactly(
        [1, 'SSH_KEY', 'new-secret', { filter: { environment_scope: '*' } }]
      )
      expect(mock_client.instance_variable_get(:@remove_variable)).to contain_exactly(
        [1, 'SSH_KEY', { filter: { environment_scope: 'prod' } }],
        [1, 'SSH_KEY', { filter: { environment_scope: 'staging' } }]
      )
      expect(output).to include('PERMANENTLY DELETED')
      expect(output).to include('(scope: prod)')
    end

    it 'targets a specific scope without deleting other scopes' do
      opts = batch_opts.merge(scope: 'prod')
      projects = [create_project(1, 'group/one')]
      vars = { 1 => [create_var('SSH_KEY', scope: 'prod'), create_var('SSH_KEY', scope: 'staging')] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)

      editor = create_editor_for_test(opts)
      capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }

      expect(mock_client.instance_variable_get(:@remove_variable)).to be_nil
      expect(mock_client.instance_variable_get(:@update_variable)).to contain_exactly(
        [1, 'SSH_KEY', 'new-secret', { filter: { environment_scope: 'prod' } }]
      )
    end

    it 'cancels and performs no writes when user answers no' do
      opts = batch_opts.merge(force: false)
      projects = [create_project(1, 'group/one')]
      vars = { 1 => [create_var('SSH_KEY'), create_var('SSH_KEY', scope: 'prod')] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)
      allow(STDIN).to receive(:gets).and_return('no')

      editor = create_editor_for_test(opts)

      expect do
        capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }
      end.to raise_error(SystemExit)

      expect(mock_client.instance_variable_get(:@update_variable)).to be_nil
      expect(mock_client.instance_variable_get(:@remove_variable)).to be_nil
    end

    it 'does nothing when there is nothing to do' do
      projects = [create_project(1, 'group/one')]
      vars = { 1 => [] }
      mock_client = create_batch_client(projects, vars)
      allow(Gitlab).to receive(:client).and_return(mock_client)

      editor = create_editor_for_test(batch_opts)
      output = capture_stdout { editor.batch_update('SSH_KEY', 'new-secret') }

      expect(output).to include('Nothing to do.')
      expect(mock_client.instance_variable_get(:@update_variable)).to be_nil
    end

    describe 'reading VALUE from stdin' do
      let(:stdin_editor_opts) { batch_opts }

      def run_batch_stdin(editor, client, *args)
        capture_stdout { editor.batch_update(*args) }
        client
      end

      it 'reads a multi-line value from stdin when VALUE is omitted and strips one trailing newline' do
        projects = [create_project(1, 'group/one')]
        vars = { 1 => [create_var('SSH_KEY')] }
        mock_client = create_batch_client(projects, vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)
        allow($stdin).to receive(:read).and_return("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\nline3\n")

        editor = create_editor_for_test(stdin_editor_opts)
        run_batch_stdin(editor, mock_client, 'SSH_KEY')

        update_args = mock_client.instance_variable_get(:@update_variable).first
        expect(update_args[2]).to eq("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\nline3")
      end

      it 'reads from stdin when VALUE argument is empty string' do
        projects = [create_project(1, 'group/one')]
        vars = { 1 => [create_var('SSH_KEY')] }
        mock_client = create_batch_client(projects, vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)
        allow($stdin).to receive(:read).and_return("piped-value\n")

        editor = create_editor_for_test(stdin_editor_opts)
        run_batch_stdin(editor, mock_client, 'SSH_KEY', '')

        update_args = mock_client.instance_variable_get(:@update_variable).first
        expect(update_args[2]).to eq('piped-value')
      end

      it 'prompts on /dev/tty for confirmation after stdin was consumed and cancels on no' do
        opts = stdin_editor_opts.merge(force: false)
        projects = [create_project(1, 'group/one')]
        vars = { 1 => [create_var('SSH_KEY')] }
        mock_client = create_batch_client(projects, vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)
        allow($stdin).to receive(:read).and_return("secret\n")

        editor = create_editor_for_test(opts)
        allow(editor).to receive(:open_tty).and_return(StringIO.new("no\n"))

        expect do
          capture_stdout { editor.batch_update('SSH_KEY') }
        end.to raise_error(SystemExit)

        expect(mock_client.instance_variable_get(:@update_variable)).to be_nil
      end

      it 'applies changes when tty confirmation answers yes' do
        opts = stdin_editor_opts.merge(force: false)
        projects = [create_project(1, 'group/one')]
        vars = { 1 => [create_var('SSH_KEY')] }
        mock_client = create_batch_client(projects, vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)
        allow($stdin).to receive(:read).and_return("secret\n")

        editor = create_editor_for_test(opts)
        allow(editor).to receive(:open_tty).and_return(StringIO.new("y\n"))

        run_batch_stdin(editor, mock_client, 'SSH_KEY')

        expect(mock_client.instance_variable_get(:@update_variable)).not_to be_nil
      end

      it 'exits with guidance when stdin is consumed and no terminal is available' do
        opts = stdin_editor_opts.merge(force: false)
        projects = [create_project(1, 'group/one')]
        vars = { 1 => [create_var('SSH_KEY')] }
        mock_client = create_batch_client(projects, vars)
        allow(Gitlab).to receive(:client).and_return(mock_client)
        allow($stdin).to receive(:read).and_return("secret\n")

        editor = create_editor_for_test(opts)
        allow(editor).to receive(:open_tty).and_return(nil)

        output = capture_stdout do
          begin
            editor.batch_update('SSH_KEY')
          rescue SystemExit
            # expected: command exits when it cannot prompt for confirmation
          end
        end
        expect(output).to include('Re-run with --force')
        expect(mock_client.instance_variable_get(:@update_variable)).to be_nil
      end
    end
  end
end

def paginated_array(array)
  array.define_singleton_method(:auto_paginate) { |&block| block ? each(&block) : array }
  array
end

def capture_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original_stdout
end