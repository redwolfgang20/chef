
require 'chef/config'
require 'chef/cookbook_version'
require 'chef/cookbook/metadata'

class Chef
  class Cookbook
    class CookbookVersionLoader

      FILETYPES_SUBJECT_TO_IGNORE = [ :attribute_filenames,
                                      :definition_filenames,
                                      :recipe_filenames,
                                      :template_filenames,
                                      :file_filenames,
                                      :library_filenames,
                                      :resource_filenames,
                                      :provider_filenames]


      attr_reader :cookbook_name
      attr_reader :cookbook_settings
      attr_reader :metadata_filenames

      def initialize(path)
        @cookbook_path = File.expand_path( path )
        @cookbook_name = File.basename( path )
        @metadata = Hash.new
        @relative_path = /#{Regexp.escape(@cookbook_path)}\/(.+)$/
        @cookbook_settings = {
          :attribute_filenames  => {},
          :definition_filenames => {},
          :recipe_filenames     => {},
          :template_filenames   => {},
          :file_filenames       => {},
          :library_filenames    => {},
          :resource_filenames   => {},
          :provider_filenames   => {},
          :root_filenames       => {}
        }

        @metadata_filenames = []
        @ignore_regexes     = []
      end

      def load_cookbooks
        @ignore_regexes = load_ignore_file(File.join(@cookbook_name, "ignore"))

        load_as(:attribute_filenames, 'attributes', '*.rb')
        load_as(:definition_filenames, 'definitions', '*.rb')
        load_as(:recipe_filenames, 'recipes', '*.rb')
        load_as(:library_filenames, 'libraries', '*.rb')
        load_recursively_as(:template_filenames, "templates", "*")
        load_recursively_as(:file_filenames, "files", "*")
        load_recursively_as(:resource_filenames, "resources", "*.rb")
        load_recursively_as(:provider_filenames, "providers", "*.rb")
        load_root_files

        if File.exists?(File.join(@cookbook_name, "metadata.json"))
          cookbook_settings[:metadata_filenames] << File.join(@cookbook_name, "metadata.json")
        end

        if empty?
          Chef::Log.warn "found a directory #{cookbook_name} in the cookbook path, but it contains no cookbook files. skipping."
        end

        remove_ignored_files
      end

      def cookbook_version
        return nil if emtpy?

        cb_version = Chef::CookbookVersion.new(@cookbook_name)

        Chef::CookbookVersion.new(cookbook).tap do |c|
          c.root_dir             = cookbook_settings[:root_dir]
          c.attribute_filenames  = cookbook_settings[:attribute_filenames].values
          c.definition_filenames = cookbook_settings[:definition_filenames].values
          c.recipe_filenames     = cookbook_settings[:recipe_filenames].values
          c.template_filenames   = cookbook_settings[:template_filenames].values
          c.file_filenames       = cookbook_settings[:file_filenames].values
          c.library_filenames    = cookbook_settings[:library_filenames].values
          c.resource_filenames   = cookbook_settings[:resource_filenames].values
          c.provider_filenames   = cookbook_settings[:provider_filenames].values
          c.root_filenames       = cookbook_settings[:root_filenames].values
          c.metadata_filenames   = cookbook_settings[:metadata_filenames]
          c.metadata             = metadata
        end
      end

      def metadata
        @metadata = Chef::Cookbook::Metadata.new(@cookbook_name)
        @metadata_filenames.each do |meta_json|
          begin
            @metadata.from_json(IO.read(meta_json))
          rescue JSON::ParserError
            Chef::Log.fatal("Couldn't parse JSON in " + meta_json)
            raise
          end
        end
        @metadata
      end

      def empty?
        cookbook_settings.inject(true) do |all_empty, files|
          all_empty && files.last.empty?
        end
      end

      def merge!(other_cookbook_loader)
        @cookbook_settings.merge!(other_cookbook_loader.cookbook_settings)
        @metadata_filenames.concat(other_cookbook_loader.metadata_filenames)
      end

      def load_ignore_file(ignore_file)
        results = Array.new
        if File.exists?(ignore_file) && File.readable?(ignore_file)
          IO.foreach(ignore_file) do |line|
            next if line =~ /^#/
            next if line =~ /^\w*$/
            line.chomp!
            results << Regexp.new(line)
          end
        end
        results
      end

      def remove_ignored_files
        @ignore_regexes.each do |regex|
          settings = cookbook_settings
          FILETYPES_SUBJECT_TO_IGNORE.each do |file_type|
            settings[file_type].delete_if { |uniqname, fullpath| fullpath.match(regex) }
          end
        end
      end

      def load_root_files
        Dir[File.join(@cookbook_path, '*'), File::FNM_DOTMATCH].each do |file|
          next if File.directory?(file)
          @cookbook_settings[:root_files][file[@relative_path, 1]] = file
        end
      end

      def load_recursively_as(category, category_dir, glob)
        file_spec = File.join(@cookbook_path, category_dir, '**', glob)
        Dir[file_spec, File::FNM_DOTMATCH].each do |file|
          next if File.directory?(file)
          @cookbook_settings[category][file[@relative_path, 1]] = file
        end
      end

      def load_as(category, *path_glob)
        Dir[File.join(@cookbook_path, *path_glob)].each do |file|
          @cookbook_settings[File.basename(file)] = file
        end
      end

    end
  end
end
