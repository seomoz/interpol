module Interpol
  module ConfigurationRuby18Extensions
    def deserialized_hash_from(file)
      YAML.load(yaml_content_for file).tap do |yaml|
        if bad_class = bad_deserialized_yaml(yaml)
          raise ConfigurationError.new \
            "Received an error while loading YAML from #{file}: \"" +
            "Got object of type: #{bad_class}\"\n If you are using YAML merge keys " +
            "to declare shared types, you must configure endpoint_definition_merge_key_files " +
            "before endpoint_definition_files."
        end
      end
    end

    # returns nil if the YAML has been only partially deserialized by Syck
    # and there are YAML::Syck objects.
    def bad_deserialized_yaml(yaml)
      if [Hash, Array].include? yaml.class
        yaml.map { |elem| bad_deserialized_yaml(elem) }.compact.first
      elsif yaml.class.name =~ /YAML::Syck::/
        yaml.class.name # Bad!
      else
        nil
      end
    end
  end
end
