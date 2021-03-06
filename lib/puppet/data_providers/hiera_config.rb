require 'pathname'
require_relative 'hiera_interpolate'

module Puppet::DataProviders
  class HieraConfig
    include Puppet::Plugins::DataProviders
    include HieraInterpolate

    DEFAULT_CONFIG = {
      'version' => 4,
      'datadir' => 'data',
      'hierarchy' => [
        {
          'name' => 'common',
          'backend' => 'yaml'
        }
      ]
    }.freeze

    def self.config_type
      @@CONFIG_TYPE ||= create_config_type
    end

    def self.symkeys_to_string(struct)
      case(struct)
      when Hash
        Hash[struct.map { |k,v| [k.to_s, symkeys_to_string(v)] }]
      when Array
        struct.map { |v| symkeys_to_string(v) }
      else
        struct
      end
    end

    def self.create_config_type
      hierarchy_elem_type_base = 'Struct[{'\
        'backend=>String[1],'\
        'name=>String[1],'\
        'datadir=>Optional[String[1]]'

      hierarchy_elem_type_v1 = hierarchy_elem_type_base + ',path=>String[1]}]'
      hierarchy_elem_type_v2 = hierarchy_elem_type_base + ',paths=>Array[String[1]]}]'
      hierarchy_elem_type_v3 = hierarchy_elem_type_base + '}]'

      Puppet::Pops::Types::TypeParser.new.parse('Struct[{'\
        'version=>Integer[4],'\
        "hierarchy=>Optional[Array[Variant[#{hierarchy_elem_type_v1},#{hierarchy_elem_type_v2},#{hierarchy_elem_type_v3}]]],"\
        'datadir=>Optional[String[1]]}]')
    end
    private_class_method :create_config_type

    attr_reader :config_path, :version

    # Creates a new HieraConfig from the given _config_root_. This is where the 'hiera.yaml' is expected to be found
    # and is also the base location used when resolving relative paths.
    #
    # @param config_root [Pathname] Absolute path to the configuration root
    # @api public
    def initialize(config_root)
      @config_root = config_root
      @config_path = config_root + 'hiera.yaml'
      if @config_path.exist?
        @config = validate_config(HieraConfig.symkeys_to_string(YAML.load_file(@config_path)))
        @config['hierarchy'] ||= DEFAULT_CONFIG['hierarchy']
        @config['datadir'] ||= DEFAULT_CONFIG['datadir']
      else
        @config = DEFAULT_CONFIG
      end
      @version = @config['version']
    end

    def create_data_providers(lookup_invocation)
      injector = Puppet.lookup(:injector)
      service_type = Registry.hash_of_path_based_data_provider_factories
      default_datadir = @config['datadir']

      # Hashes enumerate their values in the order that the corresponding keys were inserted so it's safe to use
      # a hash for the data_providers.
      data_providers = {}
      @config['hierarchy'].each do |he|
        name = he['name']
        raise Puppet::DataBinding::LookupError, "#{path}: Name '#{name}' defined more than once" if data_providers.include?(name)
        original_paths = he['paths']
        if original_paths.nil?
          single_path = he['path']
          single_path = name if single_path.nil?
          original_paths = [single_path]
        end
        paths = original_paths.map { |path| interpolate(path, lookup_invocation, false)}
        provider_name = he['backend']
        provider_factory = injector.lookup(nil, service_type, PATH_BASED_DATA_PROVIDER_FACTORIES_KEY)[provider_name]
        raise Puppet::DataBinding::LookupError, "#{@config_path}: No data provider is registered for backend '#{provider_name}' " unless provider_factory

        datadir = @config_root + (he['datadir'] || default_datadir)
        resolved_paths = provider_factory.resolve_paths(datadir, original_paths, paths, lookup_invocation)
        data_providers[name] = provider_factory.create(name, resolved_paths)
      end
      data_providers.values
    end

    def validate_config(hiera_config)
      Puppet::Pops::Types::TypeAsserter.assert_instance_of(@config_path, self.class.config_type, hiera_config)
    end
    private :validate_config
  end
end
