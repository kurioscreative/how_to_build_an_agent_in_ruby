# frozen_string_literal: true

require 'bundler/setup' # Allow gems from Gemfile to be required

require 'anthropic'  # Requires the Anthropic Ruby SDK for Claude API access
require 'fileutils'  # Ruby standard library for file operations

# This code includes all the functionality needed to create
# a command-line interface that allows users to interact with Claude and lets
# Claude interact with the file system through tools.

#  Structure of the code:
#
#  Tool - base class for defining tools
#    Tool::Parameter - utility class for defining parameters for tools
#
#  ReadFileTool - tool for reading file contents
#
#  ListFilesTool - tool for listing files in a directory
#
#  EditFileTool - tool for creating or modifying file contents
#
#  Agent - orchestrates the interaction between the user, Claude, and tools
#
#  InteractiveCLI - provides simple command-line interface for using the agent

# The Tool class provides a foundation for defining tools that Claude can use
# Each tool represents an action that Claude can take in the environment
# This class handles the common functionality for all tools (name, description, parameters)
# Borrowed from RubyLLM gem to simplify implementation and make later switching easier.
class Tool
  class << self
    # Get or set the tool's name
    # @param name [String, nil] The name to set, or nil to get the current name
    # @return [String] The tool's name
    def name(name = nil)
      return @name unless name

      @name = name
    end

    # Get or set the tool's description
    # @param description [String, nil] The description to set, or nil to get the current description
    # @return [String] The tool's description
    def description(description = nil)
      return @description unless description

      @description = description
    end

    # Get the tool's parameters
    # @return [Hash] The tool's parameters
    def parameters
      @parameters ||= {}
    end

    # Define a parameter for the tool
    # @param name [String] The parameter name
    # @param options [Hash] Options for the parameter (description, type, required)
    def param(name, **options)
      parameters[name] = Tool::Parameter.new(name, **options)
    end
  end

  # Instance methods that delegate to class methods for consistent access
  def name = self.class.name
  def description = self.class.description
  def parameters = self.class.parameters

  # Convert the tool to a format that the Anthropic API expects
  # This creates the JSON schema that Claude will use to understand the tool
  # @return [Hash] The tool definition in Anthropic's format
  def to_param
    {
      name: name,
      description: description,
      input_schema: Anthropic::Models::Tool::InputSchema.new(
        type: :object,
        properties: parameters.transform_values do |v|
          { type: v.type, description: v.description }
        end,
        required: parameters.to_h.flat_map do |k, v|
          k if v&.required
        end
      )
    }
  end

  # ToolParameter represents a single parameter for a tool
  # This class defines the structure and metadata for parameters that tools accept
  class Parameter
    attr_accessor :name, :description, :type, :required

    # Initialize a new tool parameter with name, description, type, and whether it's required
    # @param name [String] The parameter name
    # @param description [String] Human-readable description of what the parameter does
    # @param type [String] The data type of the parameter (defaults to 'string')
    # @param required [Boolean] Whether the parameter is required (defaults to true)
    def initialize(name, description:, type: 'string', required: true)
      @name = name
      @description = description
      @type = type
      @required = required
    end
  end
end

# ReadFileTool provides Claude with the ability to read file contents
# This gives Claude access to view what's in a file without modifying it
class ReadFileTool < Tool
  name 'read_file'
  description <<~DESCRIPTION
    Read the contents of a given relative file path. Use this when you want to see what's inside a file. Do not use this with directory names. No need to verify exact name and location.
  DESCRIPTION

  param :path, description: 'The relative path of a file in the working directory.'

  # Execute the read_file tool
  # @param input [Hash] Input parameters containing the path
  # @return [String] The contents of the file, or an error message
  def execute(input)
    File.read(input[:path])
  rescue StandardError => e
    { error: e.message }
  end
end

# ListFilesTool provides Claude with the ability to list files in a directory
# This helps Claude understand the file structure of the project
class ListFilesTool < Tool
  name 'list_files'

  description <<~DESCRIPTION
    List files and directories at a given path. If no path is provided, lists files in the current directory.
  DESCRIPTION

  param :path,
        description: 'Optional relative path to list files from. Defaults to current directory if not provided.'

  # Execute the list_files tool
  # @param input [Hash] Input parameters containing the optional path
  # @return [String] A string representation of the directory structure, or an error message
  def execute(input)
    root = input[:path] || '.'
    raise ArgumentError, "#{root} does not exist or is not a directory" unless File.directory?(root)

    build_directory_tree(root).to_s
  rescue StandardError => e
    { error: e.message }
  end

  private

  # Recursively build a tree representation of the directory structure
  # @param path [String] The path to build the tree from
  # @return [Hash] A nested hash representing the directory structure
  def build_directory_tree(path)
    tree = {}
    Dir.entries(path).each do |entry|
      next if ['.', '..', '.git'].include?(entry)

      full_path = File.join(path, entry)
      tree[entry] = (build_directory_tree(full_path) if File.directory?(full_path))
    end
    tree
  end
end

# EditFileTool provides Claude with the ability to create or modify file contents
class EditFileTool < Tool
  name 'edit_file'
  description <<~DESCRIPTION
    Make edits to a text file.

    Replaces 'old_str' with 'new_str' in the given file. 'old_str' and 'new_str' MUST be different from each other.

    If the file specified with path doesn't exist, it will be created.
  DESCRIPTION

  param :path, description: 'The path to the file'
  param :old_str, description: 'Text to search for - must match exactly and must only have one match exactly'
  param :new_str, description: 'Text to replace old_str with'

  # Execute the edit_file tool
  # @param input [Hash] Input parameters containing the path, old_str, and new_str
  # @return [String] A success message, or an error message
  def execute(input)
    path = input[:path]
    old_str = input[:old_str]
    new_str = input[:new_str]
    raise ArgumentError, 'Invalid arguments' if old_str == new_str || path == ''

    # If the file doesn't exist and old_str is empty, create a new file with new_str
    return create_file(path, new_str) if !File.exist?(path) && old_str.empty?

    # Read the file, replace old_str with new_str
    old_content = File.read(path)
    new_content = old_content.gsub(old_str, new_str)

    # If no changes were made, old_str wasn't found
    if old_content == new_content
      puts 'No changes made to the file.'
      return ''
    end

    # Write the new content to the file
    File.write(path, new_content, 0o644)

    'OK'
  end

  private

  # Create a new file with the given content
  # @param file_path [String] The relative path to the file to create
  # @param content [String] The content to write to the file
  # @return [String] A success message
  def create_file(file_path, content)
    # Get dir of file path
    dir = File.dirname(file_path)
    # Create directory if it doesn't exist (and it's not the current directory)
    FileUtils.mkdir_p(file_path, mode: 0o755) if dir != '.'

    # Write the content to the file
    File.write(file_path, content, 0o644)

    "Successfully created file #{file_path}"
  end
end

# The Agent class orchestrates the interaction between the user, Claude, and tools
# It manages the conversation state and executes tools when Claude requests them
class Agent
  # Initialize a new agent
  # @param client [Anthropic::Client] The Anthropic client for API access
  # @param get_user_message [Proc] A callable that gets user input
  # @param tools [Array<Tool>] An array of tools available to Claude
  def initialize(client:, get_user_message:, tools: [])
    @client = client
    @tools = tools # Array of Tool instances
    @get_user_message = get_user_message
  end

  # Execute a tool based on Claude's request
  # @param id [String] The tool use ID (for tracking in the conversation)
  # @param name [String] The name of the tool to execute
  # @param input [Hash] The input parameters for the tool
  # @return [Anthropic::Models::ToolResultBlockParam] The result of the tool execution
  def execute_tool(id, name, input)
    # Find the tool by name
    tool = @tools.find { |t| t.name == name }
    unless tool
      return Anthropic::Models::ToolResultBlockParam.new(tool_use_id: id, content: 'tool not found',
                                                         is_error: true)
    end

    begin
      print "\u001b[92mtool\u001b[0m: #{name}(#{input})\n"

      # Execute the tool and return the result
      result = tool.execute(input)

      Anthropic::Models::ToolResultBlockParam.new(
        type: :tool_result,
        tool_use_id: id,
        content: result
      )
    rescue Anthropic::Errors::Error => e
      # Handle errors from tool execution
      puts "ERROR: #{e}"
      Anthropic::Models::ToolResultBlockParam.new(
        tool_use_id: id,
        content: e.message,
        is_error: true
      )
    end
  end

  # Send the conversation to Claude and get a response
  # @param conversation [Array<Hash>] The conversation history
  # @return [Anthropic::Models::Message] Claude's response
  def run_inference(conversation)
    # Convert the tools to the format expected by the Anthropic API
    anthropic_tools = @tools.map(&:to_param)

    # Send the conversation to Claude
    @client.messages.create(
      max_tokens: 1024,
      messages: conversation,
      model: 'claude-3-5-sonnet-latest',
      tools: anthropic_tools
    )
  end

  # The main loop that manages the conversation
  # This is the heart of the agent, handling the back-and-forth between user,
  # Claude, and tools
  def run
    # Initialize an empty conversation history
    conversation = [] # Array of message params for the Anthropic API

    puts "Chat with Claude (use 'ctrl-c' to quit)"

    # Whether to read user input or continue with tool results
    read_user_input = true
    loop do
      if read_user_input
        # Get input from the user
        print "\u001b[94mYou\u001b[0m: "
        user_input = @get_user_message.call
        break if user_input.nil? # Exit if the user presses Ctrl+D

        # Add the user's message to the conversation
        user_message = Anthropic::Models::Message.new(role: :user, content: user_input)
        conversation << user_message.to_h
      end

      begin
        # Send the conversation to Claude and get a response
        message = run_inference(conversation)
      rescue Anthropic::Errors::Error => e
        # Handle API errors
        puts "API ERROR: #{e}"
        return e.message
      rescue StandardError => e
        puts "ERROR: #{e}"
        return e.message
      end

      # Add Claude's response to the conversation
      conversation << Anthropic::Models::Message.new(role: :assistant, content: message.content).to_h

      # Storage for tool results
      tool_results = []

      # Process Claude's response content blocks
      message.content.each do |content|
        case content.type
        when :text
          # Print Claude's text response
          print "\u001b[93mClaude\u001b[0m: #{content.text}\n"
        when :tool_use
          # Execute the tool Claude wants to use
          result = execute_tool(content.id, content.name, content.input)
          tool_results << result
        end
      end

      # If no tools were used, continue to get user input
      if tool_results.empty?
        read_user_input = true
        next
      end

      # If tools were used, add the results to the conversation and continue
      read_user_input = false
      conversation << Anthropic::Models::Message.new(role: :user, content: tool_results).to_h
    end
  end
end

# InteractiveCLI provides a simple command-line interface for using the agent
# This is the entry point for the application
class InteractiveCLI
  # Initialize the CLI with an Anthropic client and tools
  def initialize
    # Create the Anthropic client using the API key from environment variables
    puts "\nInitializing Anthropic client..."
    # raise 'ANTHROPIC_API_KEY environment variable not set' unless ENV['ANTHROPIC_API_KEY']
    @client = Anthropic::Client.new(
      api_key: ENV['ANTHROPIC_API_KEY']
    )
    # Initialize the available tools
    @tools = [ReadFileTool.new, ListFilesTool.new, EditFileTool.new]
  end

  # Get a message from the user via standard input
  # @return [String, nil] The user's message, or nil if Ctrl+D was pressed
  def get_user_message
    input = $stdin.gets&.chomp
    return nil if input.nil?

    input
  end

  # Run the CLI
  def run
    # Create and run the agent
    agent = Agent.new client: @client, tools: @tools, get_user_message: -> { get_user_message }
    agent.run
  end
end

# If this file is run directly, create an instance of InteractiveCLI and run it
InteractiveCLI.new.run if __FILE__ == $PROGRAM_NAME
