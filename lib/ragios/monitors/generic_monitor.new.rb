module Ragios
  module Monitors
    class GenericMonitor
      attr_reader :plugin, :cached_plugins, :notifiers, :cached_notifiers, :id, :test_result, :interval, :time_of_test, :options

      def initialize
        @cached_plugins = []
        @cached_notifiers = []

        super()
      end

      def init(options, skip_extensions_creation = false)
        reset
        @options = options
        @id = @options[:_id] if options[:_id]
        @interval = @options[:every]
        unless skip_extensions_creation
          create_plugin
          create_notifiers
        end
      end

      def reset
        @id = nil
        @state = nil
        @test_result = nil
        @time_of_test = nil
        @interval = nil
      end

      def create_plugin
        raise_plugin_not_found unless @options.has_key?(:plugin)

        @plugin = cached_extension(:plugin, @options[:plugin], cached_plugins)
=begin
        plugin_from_cache = cached_plugins.find do |plugin|
          plugin.class.name == @options[:plugin]
        end

        @plugin =
          if plugin_from_cache
            plugin_from_cache
          else
            new_plugin = GenericMonitor.build_extension(:plugin, @options[:plugin])
            cached_plugins << new_plugin
            new_plugin
          end
=end
        validate_plugin(@plugin)
        @plugin.init(options)
      end

      def create_notifiers
        raise_notifier_not_found unless @options.has_key?(:via)
        @options[:via] = [] << @options[:via] if @options[:via].is_a? String
        raise_notifier_not_found if @options[:via].empty?
        @notifiers = @options[:via].map do |notifier_name|

          notifier = cached_extension(:notifier, notifier_name, cached_notifiers)
=begin
          notifier_from_cache = cached_notifiers.find do |n|
            n.class.name == notifier_name
          end

          notifier =
            if notifier_from_cache
              notifier_from_cache
            else
              new_notifier = GenericMonitor.build_extension(:notifier, notifier_name)
              cached_notifiers << new_notifier
              new_notifier
            end
=end
          validate_notifier(notifier)
          notifier.init(@options)
          notifier
        end
      end
    end

    def cached_extension(extension_type, extension_name, cached_extensions)
      extension_from_cache = cached_extensions.find do |extension|
        extension.class.name == extension_name
      end

      if extension_from_cache
        extension_from_cache
      else
        new_extension = GenericMonitor.build_extension(extension_type, extension_name)
        cached_extensions << new_extension
        new_extension
      end
    end
  end
end
