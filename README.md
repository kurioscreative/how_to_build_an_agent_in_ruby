# How to Build a Code Editing Agent in Ruby

A lightweight command-line interface that allows you to interact with Claude AI and gives Claude the ability to read, list, and edit files in your system.

## Motivation
I built this as an exploration in Ruby of Thorsten Ball's Go code from "[How to Build An Agent](https://ampcode.com/how-to-build-an-agent)". I kept the code closer to the Go patterns to make it easier to follow along with his post.

## Overview

This project implements a simple but powerful agent that:

1. Connects to Claude via the Anthropic API
2. Creates a command-line chat interface
3. Provides Claude with tools to interact with your file system:
   - Reading files
   - Listing directory contents
   - Editing files (via string replacement)

In under 300 lines of Ruby code, you can code an AI assistant that can help you write code, modify files, and explore your project structure.

## Requirements

- Ruby 3.0+
- An Anthropic API key ([Anthropic API Console](https://console.anthropic.com/settings/keys))

## Installation

This project is designed to be simple with just two key files: agent.rb and an executable agent_cli.

Clone this repository to try it out:
```bash
git clone https://github.com/kurioscreative/how_to_build_an_agent_in_ruby.git
cd how_to_build_an_agent_in_ruby
```

Install the only dependency (anthropic gem):
```base
bundle install
```

Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY=your_api_key_here
```

Make the CLI executable (optional):
```bash
chmod +x agent_cli
```

## Usage
Run the agent:

```
ruby agent.rb
```

Or, if you made the CLI executable:
```
./agent_cli
```
You'll enter a chat interface where you can interact with Claude. The agent will automatically detect when Claude wants to use a tool and will execute it, then return the results to Claude.

### Example Usage

```
Chat with Claude (use 'ctrl-c' to quit)

You: What files do we have in this directory?

Claude: I'll check what files are in the current directory.

tool: list_files({})

Claude: I found the following files and directories in the current directory:
- agent_cli
- Gemfile
- Gemfile.lock
- README.md
- lib/
- spec/

You: Create a simple hello.rb file that prints "Hello, World!"

Claude: I'll create a simple hello.rb file for you.

tool: edit_file({"path":"hello.rb","old_str":"","new_str":"#!/usr/bin/env ruby\n\nputs \"Hello, World!\""})

Claude: I've created the hello.rb file with a simple "Hello, World!" program. The file contains:
1. A shebang line (#!/usr/bin/env ruby) to make it executable
2. A puts statement that prints "Hello, World!"

You can run it with:
`ruby hello.rb`

Or make it executable and run it directly:

`chmod +x hello.rb`
`./hello.rb`

```

## How It Works

The agent works through a simple but powerful mechanism:

1. **Tools Definition**: Each tool (read_file, list_files, edit_file) is defined with a name, description, parameters, and an execution function.

2. **Conversation Loop**: The agent maintains a conversation between you and Claude, passing messages back and forth.

3. **Tool Execution**: When Claude wants to use a tool, it includes a specific format in its response that the agent recognizes. The agent then:
   - Extracts the tool name and parameters
   - Executes the appropriate tool
   - Adds the result to the conversation
   - Sends the updated conversation back to Claude

4. **Continuous Flow**: The agent continues this loop, allowing Claude to chain multiple tool uses together to accomplish complex tasks.

## Project Structure

```
how_to_build_an_agent_in_ruby/
├── agent.rb   # Main application file
├── agent_cli   # CLI executable
├── Gemfile              # Dependencies
├── README.md            # This file
```

## Available Tools

### 1. read_file

Reads the contents of a file at a given path.

Parameters:
- `path`: The relative path to the file

### 2. list_files

Lists all files and directories at a given path.

Parameters:
- `path`: (Optional) The relative path to list. Defaults to current directory.

### 3. edit_file

Creates or modifies a file by replacing text.

Parameters:
- `path`: The path to the file
- `old_str`: Text to search for and replace (empty string if creating a new file)
- `new_str`: Text to replace with or file contents for a new file

## Extending the Agent

You can easily add new tools to the agent by:

1. Creating a new class that inherits from `Tool`
2. Defining the tool's name, description, and parameters
3. Implementing an `execute` method
4. Adding an instance of your tool to the `@tools` array in `InteractiveCLI#initialize`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kurioscreative/how_to_build_an_agent_in_ruby.

## License

The code is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgements

Inspired by the blog post "How to Build an Agent in Go" by Thorsten Ball.
