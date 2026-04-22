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
    client.define_singleton_method(:variables) { |*_args| variables }
    client.define_singleton_method(:update_variable) { |*_args| }
    client.define_singleton_method(:create_variable) { |*_args| }
    client.define_singleton_method(:delete_variable) do |_project, key|
      @deleted ||= []
      @deleted << key
    end
    client.instance_variable_set(:@deleted, [])
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

        output = capture_stdout { editor.import(temp_yaml_file.path) }
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
end

def capture_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original_stdout
end