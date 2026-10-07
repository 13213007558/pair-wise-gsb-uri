# frozen_string_literal: true

require_relative 'generic'

module URI

  # Uniform Resource Name as defined by RFC 8141.
  #
  # The NID, NSS, r-component, q-component, and fragment are available as
  # separate components. Use #syntactic_equivalent? for lexical equivalence of
  # the URN and NSS, and #namespace_specific_equivalent? for an instance-level
  # namespace policy.
  class URN < Generic
    COMPONENT = %i[scheme nid nss r_component q_component fragment].freeze

    NID = /
      \A(?:
        (?!urn-)[0-9A-Za-z][0-9A-Za-z-]{0,30}[0-9A-Za-z] |
        urn-[0-9A-Za-z](?:[0-9A-Za-z-]{0,30}[0-9A-Za-z])?
      )\z
    /x.freeze

    UNRESERVED = /[A-Za-z0-9\-._~]/.freeze
    PERCENT_ENCODED = /%[0-9A-Fa-f]{2}/.freeze
    NSS = /\A(?:#{PERCENT_ENCODED}|[0-9A-Za-z\-._~!$&'()*+,;=:@])+\z/x.freeze
    COMPONENT_DATA = /\A(?:#{PERCENT_ENCODED}|[0-9A-Za-z\-._~!$&'()*+,;=:@\/?])+\z/x.freeze
    FRAGMENT_DATA = /\A(?:#{PERCENT_ENCODED}|[0-9A-Za-z\-._~!$&'()*+,;=:@\/?])*\z/x.freeze

    class MissingNamespacePolicyError < Error; end

    def self.build(args)
      components = args.kind_of?(Hash) ? args : Hash[COMPONENT.zip(args)]
      components[:scheme] ||= 'urn'
      new(
        components[:scheme],
        components[:nid],
        components[:nss],
        components[:r_component],
        components[:q_component],
        components[:fragment],
        components[:parser] || DEFAULT_PARSER,
        namespace_specific_policy: components[:namespace_specific_policy]
      )
    end

    def self.parse(urn, parser = DEFAULT_PARSER)
      nid, nss, r_component, q_component, fragment = split(urn)
      new('urn', nid, nss, r_component, q_component, fragment, parser)
    end

    def self.split(urn)
      urn = urn.to_str
      raise InvalidURIError, "URN must be ASCII only #{urn.dump}" unless urn.ascii_only?

      reference, fragment = urn.split('#', 2)
      match = /\A([A-Za-z][+\-.0-9A-Za-z]*):([^:?#]+):(.*)\z/m.match(reference)
      unless match && match[1].casecmp?('urn')
        raise InvalidURIError, "bad URN (is not URN?): #{urn.inspect}"
      end

      nid = match[2].downcase
      nss, r_component, q_component = split_namestring(match[3])
      if q_component && q_component.include?('?+')
        raise InvalidURIError, "q-component cannot contain an r-component"
      end
      validate_nid!(nid)
      validate_component!(:nss, nss, NSS)
      validate_component!(:r_component, r_component, COMPONENT_DATA) if r_component
      validate_component!(:q_component, q_component, COMPONENT_DATA) if q_component
      validate_component!(:fragment, fragment, FRAGMENT_DATA) unless fragment.nil?

      [nid, nss, r_component, q_component, fragment]
    end

    def self.split_namestring(rest)
      r_index = rest.index('?+')
      q_index = rest.index('?=')

      if r_index && q_index && q_index < r_index
        raise InvalidURIError, "q-component cannot precede r-component"
      end

      if r_index && (q_index.nil? || r_index < q_index)
        nss = rest[0, r_index]
        after_r = rest[(r_index + 2)..-1]
        q_at = after_r.index('?=')
        if q_at
          [nss, after_r[0, q_at], after_r[(q_at + 2)..-1]]
        else
          [nss, after_r, nil]
        end
      elsif q_index
        [rest[0, q_index], nil, rest[(q_index + 2)..-1]]
      else
        [rest, nil, nil]
      end
    end
    private_class_method :split_namestring

    def self.validate_nid!(nid)
      unless nid && NID.match?(nid)
        raise InvalidURIError, "bad component(expected NID component): #{nid.inspect}"
      end
    end
    private_class_method :validate_nid!

    def self.validate_component!(name, value, pattern)
      if value.nil? || !pattern.match?(value)
        raise InvalidURIError, "bad component(expected #{name} component): #{value.inspect}"
      end
    end
    private_class_method :validate_component!

    attr_reader :nid, :nss, :r_component, :q_component
    attr_reader :namespace_specific_policy

    def initialize(scheme, nid, nss, r_component = nil, q_component = nil,
                   fragment = nil, parser = DEFAULT_PARSER,
                   namespace_specific_policy: nil)
      unless scheme&.casecmp?('urn')
        raise InvalidComponentError, "bad component(expected scheme component): #{scheme.inspect}"
      end
      self.class.send(:validate_nid!, nid)
      self.class.send(:validate_component!, :nss, nss, NSS)
      check_urn_component(:r_component, r_component)
      check_urn_component(:q_component, q_component)
      check_urn_component(:fragment, fragment, FRAGMENT_DATA)

      super(scheme, nil, nil, nil, nil, nil, "#{nid.downcase}:#{nss}", nil,
            fragment, parser, false)

      @nid = nid.downcase
      @nss = nss
      @r_component = r_component
      @q_component = q_component
      self.namespace_specific_policy = namespace_specific_policy
    end

    def namespace_specific_policy=(policy)
      if policy && !policy.respond_to?(:call)
        raise ArgumentError, "namespace-specific equivalence policy must be callable"
      end
      @namespace_specific_policy = policy
    end

    def nid=(value)
      self.class.send(:validate_nid!, value)
      @nid = value.downcase
      set_opaque("#{@nid}:#{@nss}")
      value
    end

    def nss=(value)
      self.class.send(:validate_component!, :nss, value, NSS)
      @nss = value
      set_opaque("#{@nid}:#{@nss}")
      value
    end

    def r_component=(value)
      check_urn_component(:r_component, value)
      if value && @q_component
        raise InvalidComponentError, "r-component cannot follow q-component"
      end
      @r_component = value
    end

    def q_component=(value)
      check_urn_component(:q_component, value)
      @q_component = value
    end

    def fragment=(value)
      check_urn_component(:fragment, value, FRAGMENT_DATA)
      @fragment = value
    end

    def query
      nil
    end

    def query=(value)
      raise InvalidURIError, "URN uses r-component and q-component, not query" unless value.nil?
      nil
    end

    def opaque
      "#{@nid}:#{@nss}"
    end

    def opaque=(value)
      parsed_nid, parsed_nss, parsed_r, parsed_q, = self.class.split("urn:#{value}")
      @nid = parsed_nid
      @nss = parsed_nss
      @r_component = parsed_r
      @q_component = parsed_q
      set_opaque("#{@nid}:#{@nss}")
      value
    end

    def normalize!
      set_scheme('urn')
      @nss = normalize_percent_encoding(@nss)
      set_opaque("#{@nid}:#{@nss}")
      self
    end

    def to_s
      result = "urn:#{@nid}:#{@nss}"
      result << "?+#{@r_component}" if @r_component
      result << "?=#{@q_component}" if @q_component
      result << "##{@fragment}" if @fragment
      result
    end

    # Returns whether the scheme, NID, and NSS are lexically equivalent.
    #
    # r-components, q-components, and fragments are not considered.
    def syntactic_equivalent?(other)
      other = coerce_urn(other)
      syntactic_key == other.send(:syntactic_key)
    end
    alias lexical_equivalent? syntactic_equivalent?
    alias lexically_equivalent? syntactic_equivalent?

    # Returns whether +other+ is equivalent according to the receiver's
    # namespace-specific policy.
    #
    # Raises MissingNamespacePolicyError when the receiver has no policy.
    def namespace_specific_equivalent?(other)
      other = coerce_urn(other)
      unless nid == other.nid
        return false
      end
      unless namespace_specific_policy.respond_to?(:call)
        raise MissingNamespacePolicyError,
          "no namespace-specific equivalence policy registered for #{@nid}"
      end
      !!namespace_specific_policy.call(self, other)
    end

    # Sets the callable used by #namespace_specific_equivalent?.
    #
    # The callable is called with the receiver and the other URN.
    def register_namespace_specific_policy(policy)
      self.namespace_specific_policy = policy
    end

    def ==(other)
      other.is_a?(URN) &&
        syntactic_equivalent?(other) &&
        r_component == other.r_component &&
        q_component == other.q_component &&
        fragment == other.fragment
    end

    def hash
      [self.class, syntactic_key, @r_component, @q_component, @fragment].hash
    end

    def eql?(other)
      other.is_a?(URN) && parser == other.parser && self == other
    end

    def hierarchical?
      false
    end

    private

    def check_urn_component(name, value, pattern = COMPONENT_DATA)
      return if value.nil?
      unless value.is_a?(String) && pattern.match?(value)
        raise InvalidComponentError,
          "bad component(expected #{name} component): #{value.inspect}"
      end
    end

    def normalize_percent_encoding(value)
      value.gsub(PERCENT_ENCODED) do |encoded|
        byte = encoded[1, 2].to_i(16).chr(Encoding::BINARY)
        if UNRESERVED.match?(byte)
          byte.force_encoding(Encoding::US_ASCII)
        else
          "%#{encoded[1, 2].upcase}"
        end
      end
    end

    def syntactic_key
      [@nid, normalize_percent_encoding(@nss)]
    end

    def coerce_urn(other)
      return other if other.is_a?(URN)
      return parser.parse(other) if String.try_convert(other)
      raise ArgumentError, "bad argument (expected URN object or URN string)"
    end
  end

  register_scheme 'URN', URN
end
