module HerokuPlus
  module Utilities
    # Prints info to the console.
    def say_info message
      say_status :info, message, :white
    end

    # Prints an error to the console.
    def say_error message
      say_status :error, message, :red
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
      File.exists?(file) ? true : (say_error("ERROR: #{message}: #{file}.") and false)
    end

    # Backup (duplicate) existing file to new file.
    # ==== Parameters
    # * +old_file+ - Required. The file to be backed up.
    # * +new_file+ - Required. The file to backup to.
    def backup_file old_file, new_file
      if File.exists? old_file
        if File.exists? new_file
          answer = yes? "File exists: \"#{new_file}\". Do you wish to replace the existing file (y/n)?"
          if answer
            `cp #{old_file} #{new_file}`
            say_info "Replaced: #{new_file}"
          else
            say_info "Backup aborted."
          end
        else
          `cp #{old_file} #{new_file}`
          say_info "Created: #{new_file}"
        end
      else
        say_error "Backup aborted! File does not exist: #{old_file}"
      end
    end

    # Destroy an existing file.
    # ==== Parameters
    # * +file+ - Required. The file to destroy.
    def destroy_file file
      if valid_file? file
        answer = yes? "You are about to perminently destroy file: #{file}. Do you wish to continue (y/n)?"
        if answer
          `rm -f #{file}`
          say_info "Destroyed: #{file}"
        else
          say_info "Destroy aborted."
        end
      else
        say_error "Destroy aborted! File not found: #{file}"
      end
    end
  end
end