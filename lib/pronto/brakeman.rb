require 'pronto'
require 'brakeman'

module Pronto
  class Brakeman < Runner
    def run
      patches = ruby_patches | erb_patches
      any_applicable_files = patches.any? do |patch|
        patch.new_file_full_path.relative_path_from(brakeman_run_path)
        true
      rescue ArgumentError
        # Not under `brakeman_run_path`.
        false
      end

      return [] unless any_applicable_files

      output = ::Brakeman.run(app_path: brakeman_run_path,
                              output_formats: [:to_s],
                              run_all_checks: run_all_checks?,
                              ignore_file: ignore_file)
       messages_for(patches, output).compact
    rescue ::Brakeman::NoApplication
      []
    end

    def messages_for(code_patches, output)
      output.filtered_warnings.map do |warning|
        patch = patch_for_warning(code_patches, warning)

        next unless patch
        line = patch.added_lines.find do |added_line|
          added_line.new_lineno == warning.line
        end

        new_message(line, warning) if line
      end
    end

    def new_message(line, warning)
      Message.new(line.patch.delta.new_file[:path], line,
                  severity_for_confidence(warning.confidence),
                  "Possible security vulnerability: [#{warning.message}](#{warning.link})",
                  nil, self.class)
    end

    def severity_for_confidence(confidence_level)
      case confidence_level
      when 0 # Brakeman High confidence
        :fatal
      when 1 # Brakeman Medium confidence
        :warning
      else # Brakeman Low confidence (and other possibilities)
        :info
      end
    end

    def patch_for_warning(code_patches, warning)
      code_patches.find do |patch|
        patch.new_file_full_path.to_s == warning.file.absolute
      end
    end

    def brakeman_run_path
      return repo_path unless pronto_brakeman_config['path']
      File.join(repo_path, pronto_brakeman_config['path'])
    end

    def run_all_checks?
      pronto_brakeman_config['run_all_checks']
    end

    def ignore_file
      pronto_brakeman_config['ignore_file']
    end

    def pronto_brakeman_config
      pronto_brakeman_config ||= Pronto::ConfigFile.new.to_h['brakeman'] || {}
    end

    def erb_patches
      @erb_patches ||= Array(@patches).select { |patch| patch.additions > 0 }
                                      .select { |patch| erb_file?(patch.new_file_full_path) }
    end

    def erb_file?(path)
      File.extname(path) == '.erb'
    end
  end
end
