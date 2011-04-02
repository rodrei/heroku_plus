module HerokuPlus
  module Utilties
    # Executes and echos the given command line arguments.
    # ==== Parameters
    # * +args+ - Required. The command line to be executed.
    def shell_with_echo *args
      command = args * ' '
      @shell.say command
      system command
    end

    # Answer the substring of the given string within a start and end delimiter range.
    # ==== Parameters
    # * +string+ - Required. The string to search.
    # * +delimiter_start+ - Required. The start delimiter.
    # * +delimiter_end+ - Required. The end delimiter.
    def grab_substring string, delimiter_start, delimiter_end
      index = string.index(delimiter_start) + 1
      length = (string.rindex(delimiter_end) || 0) - index
      string[index, length]
    end

    # Answer whether the file exists and print an error message when not found.
    # ==== Parameters
    # * +file+ - Required. The file to validate.
    # * +message+ - Optional. The error message. Defaults to "Invalid file".
    def valid_file? file, message = "Invalid file"
      File.exists?(file) ? true : (@shell.say("ERROR: #{message}: #{file}.") and false)
    end
        
    # Backup (duplicate) existing file to new file.
    # ==== Parameters
    # * +old_file+ - Required. The file to be backed up.
    # * +new_file+ - Required. The file to backup to.
    def backup_file old_file, new_file
      if File.exists? old_file
        if File.exists? new_file
          answer = @shell.yes? "File exists: \"#{new_file}\". Do you wish to replace the existing file (y/n)?"
          if answer
            system "cp #{old_file} #{new_file}"
            @shell.say "Replaced: #{new_file}"
          else
            @shell.say "Backup aborted."
          end
        else
          system "cp #{old_file} #{new_file}"
          @shell.say "Created: #{new_file}"
        end
      else
        @shell.say "ERROR: Backup aborted! File does not exist: #{old_file}"
      end
    end

    # Destroy an existing file.
    # ==== Parameters
    # * +file+ - Required. The file to destroy.
    def destroy_file file
      if valid_file? file
        answer = @shell.yes? "You are about to perminently destroy file: #{file}. Do you wish to continue (y/n)?"
        if answer
          system "rm -f #{file}"
          @shell.say "Destroyed: #{file}"
        else
          @shell.say "Destroy aborted."
        end
      else
        @shell.say "ERROR: Destroy aborted! File not found: #{file}"
      end
    end
  end
end
