module Compass::SassExtensions::Functions::CrossBrowserSupport

  class CSS2FallbackValue < Sass::Script::Literal
    attr_accessor :value, :css2_value
    def children
      [value, css2_value]
    end
    def initialize(value, css2_value)
      self.value = value
      self.css2_value = css2_value
    end
    def inspect
      to_s
    end
    def to_s(options = self.options)
      value.to_s(options)
    end
    def supports?(aspect)
      aspect == "css2"
    end
    def has_aspect?
      true
    end
    def to_css2(options = self.options)
      css2_value
    end
  end

  # Check if any of the arguments passed require a vendor prefix.
  def prefixed(prefix, *args)
    aspect = prefix.value.sub(/^-/,"")
    needed = args.any?{|a| a.respond_to?(:supports?) && a.supports?(aspect)}
    Sass::Script::Bool.new(needed)
  end

  %w(webkit moz o ms svg pie css2).each do |prefix|
    class_eval <<-RUBY, __FILE__, __LINE__ + 1
      # Syntactic sugar to apply the given prefix
      # -moz($arg) is the same as calling prefix(-moz, $arg)
      def _#{prefix}(*args)
        prefix("#{prefix}", *args)
      end
    RUBY
  end

  def prefix(prefix, *objects)
    prefix = prefix.value if prefix.is_a?(Sass::Script::String)
    prefix = prefix[1..-1] if prefix[0] == ?-
    if objects.size > 1
      self.prefix(prefix, Sass::Script::List.new(objects, :comma))
    else
      object = objects.first
      if object.is_a?(Sass::Script::List)
        Sass::Script::List.new(object.value.map{|e|
          self.prefix(prefix, e)
        }, object.separator)
      elsif object.respond_to?(:supports?) && object.supports?(prefix) && object.respond_to?(:"to_#{prefix}")
        object.options = options
        object.send(:"to_#{prefix}")
      else
        object
      end
    end
  end

  def css2_fallback(value, css2_value)
    CSS2FallbackValue.new(value, css2_value)
  end

  # The known browsers.
  #
  # If prefix is given, limits the returned browsers to those using the specified prefix.
  def browsers(prefix = nil)
    browsers = if prefix
                 assert_type prefix, :String
                 Compass::CanIUse.instance.browsers_with_prefix(prefix.value)
               else
                 Compass::CanIUse.instance.browsers
               end
    list(browsers.map{|b| identifier(b)}, :comma)
  end
  Sass::Script::Functions.declare(:browsers, [])
  Sass::Script::Functions.declare(:browsers, [:prefix])

  # The known capabilities of browsers.
  def browser_capabilities
    list(Compass::CanIUse.instance.capabilities.map{|c| identifier(c)}, :comma)
  end
  Sass::Script::Functions.declare(:browser_capabilities, [])

  # The versions for the given browser.
  def browser_versions(browser)
    assert_type browser, :String
    list(Compass::CanIUse.instance.versions(browser.value).map{|v| quoted_string(v)}, :comma)
  rescue ArgumentError => e
    raise Sass::SyntaxError.new(e.message)
  end
  Sass::Script::Functions.declare(:browser_versions, [:browser])

  # whether the browser uses a prefix for the given capability at the version
  # specified or a later version.
  def browser_requires_prefix(browser, version, capability)
    assert_type browser, :String
    assert_type version, :String
    assert_type capability, :String
    bool(Compass::CanIUse.instance.requires_prefix(browser.value, version.value, capability.value))
  rescue ArgumentError => e
    raise Sass::SyntaxError.new(e.message)
  end
  Sass::Script::Functions.declare(:browser_requires_prefix, [:browser, :version, :capability])

  # the prefix for the given browser.
  def browser_prefix(browser)
    assert_type browser, :String
    identifier(Compass::CanIUse.instance.prefix(browser.value))
  rescue ArgumentError => e
    raise Sass::SyntaxError.new(e.message)
  end
  Sass::Script::Functions.declare(:browser_prefix, [:browser])

  # The prefixes used by the given browsers.
  def browser_prefixes(browsers)
    browsers = list(browsers, :comma) if browsers.is_a?(Sass::Script::Value::String)
    assert_type browsers, :List
    browser_strings = browsers.value.map {|b| assert_type(b, :String); b.value }
    prefix_strings = Compass::CanIUse.instance.prefixes(browser_strings)
    list(prefix_strings.map {|p| identifier(p)}, :comma)
  rescue ArgumentError => e
    raise Sass::SyntaxError.new(e.message)
  end
  Sass::Script::Functions.declare(:browser_prefixes, [:browsers])

  # The percent of users that are omitted by setting the min_version of browser
  # as specified.
  def omitted_usage(browser, min_version)
    assert_type browser, :String
    assert_type min_version, :String
    number(Compass::CanIUse.instance.omitted_usage(browser.value, min_version.value))
  end
  Sass::Script::Functions.declare(:omitted_usage, [:browser, :min_version])

  # The percent of users relying on a particular prefix
  def prefix_usage(prefix, capability)
    assert_type prefix, :String
    assert_type capability, :String
    number(Compass::CanIUse.instance.prefixed_usage(prefix.value, capability.value))
  rescue ArgumentError => e
    raise Sass::SyntaxError.new(e.message)
  end
  Sass::Script::Functions.declare(:prefix_usage, [:prefix, :capability])

  # Compares two browser versions. Returning:
  #
  # * 0 if they are the same
  # * <0 if the first version is less than the second
  # * >0 if the first version is more than the second
  def compare_browser_versions(browser, version1, version2)
    assert_type browser, :String
    assert_type version1, :String
    assert_type version2, :String
    index1 = index2 = nil
    Compass::CanIUse.instance.versions(browser.value).each_with_index do |v, i|
      index1 = i if v == version1.value
      index2 = i if v == version2.value
      break if index1 && index2
    end
    unless index1
      raise Sass::SyntaxError.new("#{version1} is not a version for #{browser}")
    end
    unless index2
      raise Sass::SyntaxError.new("#{version2} is not a version for #{browser}")
    end
    number(index1 <=> index2)
  end
  Sass::Script::Functions.declare(:compare_browser_versions, [:browser, :version1, :version2])

  # Returns a map of browsers to the first version the capability became available
  # without a prefix.
  #
  # If a prefix is provided, only those browsers using that prefix will be returned
  # and the minimum version will be when it first became available as a prefix or
  # without a prefix.
  #
  # If a browser does not have the capability, it will not included in the map.
  def browser_minimums(capability, prefix = null())
    assert_type capability, :String
    assert_type(prefix, :String) unless prefix == null()
    mins = Compass::CanIUse.instance.browser_minimums(capability.value, prefix.value)
    Sass::Script::Value::Map.new(mins.inject({}) do |m, (h, k)|
      m[identifier(h)] = quoted_string(k)
      m
    end)
  end
  Sass::Script::Functions.declare(:browser_minimums, [:capability])
  Sass::Script::Functions.declare(:browser_minimums, [:capability, :prefix])
end
