# frozen_string_literal: false
# = uri/tel.rb
#
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'generic'

module URI

  #
  # RFC3966, the tel URI for telephone numbers.
  #
  # A tel URI identifies a telephone number. It carries either a global
  # number (a "+" followed by a country code and the national number) or
  # a local number qualified by a +phone-context+ parameter. Unlike
  # naively stripping non-digit characters, this class understands RFC
  # 3966 structure: visual separators are position restricted and ignored
  # for comparison, parameter order is insignificant, parameter name
  # case is insignificant while parameter value case is generally
  # significant, +ext+ and +isub+ are mutually exclusive, and unknown
  # required parameters mark the URI as unusable by a dialing system.
  #
  class Tel < Generic
    # A Default port of nil for URI::Tel.
    DEFAULT_PORT = nil

    # An Array of the available components for URI::Tel.
    COMPONENT = [ :scheme, :number, :params ].freeze

    # Parameter names defined by RFC 3966.
    KNOWN_PARAMS = %w[phone-context isub ext].freeze
    private_constant :KNOWN_PARAMS

    # :stopdoc:
    # telephone-subscriber = global-number / local-number
    # global-number      = global-number-digits *par
    # local-number       = local-number-digits *par context *par
    # global-number-digits = "+" 1*phonedigit
    # local-number-digits  =
    #   1*(phonedigit / dtmf-digit / pause-character / wait-character)
    # phonedigit         = DIGIT / [visual-separator] 1*phonedigit
    # visual-separator   = "-" / "." / "(" / ")"
    # extension          = ";ext=" 1*(visual-separator / phonedigit)
    # isdn-subaddress    = ";isub=" 1*(visual-separator / hexdigit)
    # parameter          = ";" pname ["=" pvalue]
    GLOBAL_NUMBER_DIGITS =
      %r{\A\+[0-9]+(?:[.()\-][0-9]+)*\z}
    # Global-number-digits used as phone-context may end in a separator.
    GLOBAL_NUMBER_PREFIX =
      %r{\A\+[0-9]+(?:[.()\-][0-9]+)*[.()\-]?\z}
    LOCAL_NUMBER_DIGITS =
      %r{\A[0-9*#pwPW]+(?:[.()\-][0-9*#pwPW]+)*\z}
    # pname = 1*(param-unreserved / "!")
    # param-unreserved = unreserved / "[" / "]" / "/" / ":" / "&" / "+" / "$"
    PNAME  = %r{\A[\[\]/:&+$.!~*'()A-Za-z0-9_\-]+\z}
    # pvalue = 1*(param-unreserved / pct-encoded)
    PVALUE = %r{\A(?:%\h\h|[\[\]/:&+$.!~*'()A-Za-z0-9_\-])*\z}
    DOMAIN = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\.?\z/
    # :startdoc:

    #
    # == Description
    #
    # Creates a new URI::Tel object from components, with syntax checking.
    #
    # Components can be provided as an Array or Hash. If an Array is
    # used, the components must be supplied as +[number, params]+.
    #
    # The number is the digits of the subscriber part, such as
    # "+1-201-555-0123" for a global number or "7042" for a local
    # number. The parameters can be supplied as a pre-encoded String
    # ("phone-context=example.com"), as an Array of +[name, value]+
    # pairs (a nil or missing value denotes a valueless parameter), or
    # as a Hash.
    #
    # Examples:
    #
    #    require 'uri/tel'
    #
    #    URI::Tel.build(['+1-201-555-0123', nil]).to_s
    #    # => "tel:+1-201-555-0123"
    #
    #    URI::Tel.build(number: '7042',
    #                  params: [['phone-context', 'example.com']]).to_s
    #    # => "tel:7042;phone-context=example.com"
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)

      opaque = tmp[:number].to_s.dup
      params_from(tmp[:params]).each do |name, value|
        opaque << ';' << name.to_s
        opaque << '=' << value if value
      end
      tmp[:opaque] = opaque

      super(tmp)
    end

    #
    # Creates a new URI::Tel object from generic URL components with
    # syntax checking against RFC 3966. This is usually called from
    # URI.parse.
    #
    def initialize(*arg)
      super(*arg)

      @number = nil
      @params = []
      @global_number = nil

      unless @opaque
        raise InvalidComponentError,
          "missing opaque part for tel URL"
      end
      if @query
        raise InvalidComponentError,
          "query component is not allowed in tel URL: #{@opaque}"
      end
      if @fragment
        raise InvalidComponentError,
          "fragment component is not allowed in tel URL: #{@fragment}"
      end

      parse_opaque(@opaque)
    end

    # The subscriber number as it appeared in the URI, without any
    # parameter, e.g. "+1-201-555-0123".
    attr_reader :number

    # The URI parameters as an Array of +[name, value]+ pairs in the
    # order they appeared. Parameter name case is not significant;
    # valueless parameters have a nil value.
    attr_reader :params

    # Returns true for a global number (tel:+...), false for a local
    # number.
    def global?
      @global_number
    end

    # Returns true for a local number. A local number carries a
    # phone-context parameter.
    def local?
      !@global_number
    end

    # The dialable digits of the subscriber number with all visual
    # separators removed. Global numbers keep the leading "+". A local
    # number may still contain "*", "#", "p"/"w" characters.
    def number_digits
      strip_visual_separators(@number)
    end

    # The percent-decoded value of the named parameter, or nil when the
    # parameter is absent or valueless. The name match is
    # case-insensitive.
    def param(name)
      found = @params.find { |n, _| canonical_param_name(n) == canonical_param_name(name) }
      found && found[1] && decode(found[1])
    end

    # The percent-decoded phone-context of a local number, or nil.
    def phone_context
      param('phone-context')
    end

    # The percent-decoded extension (the value of +ext+) with all visual
    # separators removed, or nil.
    def extension
      value = param('ext')
      value && strip_visual_separators(value)
    end

    # The percent-decoded ISDN subaddress (the value of +isub+) with all
    # visual separators removed, or nil.
    def isdn_subaddress
      value = param('isub')
      value && strip_visual_separators(value)
    end

    # Names of unrecognized required parameters, i.e. parameters whose
    # name begins with "!" (other than the RFC 3966 parameters). RFC
    # 3966 5.1.5 forbids a dialing system from interpreting such URIs.
    def unusable_params
      @unusable_params.dup
    end

    # Returns true unless the URI carries an unrecognized required
    # parameter; such a URI must not be used for placing a call.
    def usable?
      @unusable_params.empty?
    end

    # Returns true if the number can be dialed without resolving a
    # phone-context: every global number, and a local number whose
    # phone-context is itself a global number prefix. No country database
    # is consulted, so other contexts (a domain or a private prefix)
    # are not resolvable here.
    def dialable?
      return true if global?
      global_context?
    end

    # Returns a structured representation usable by a dialing system:
    #
    #   URI("tel:+1-201-555-0123").to_dial
    #   # => {:scheme=>"tel", :global=>true, :number=>"+12015550123",
    #   #     :dial_string=>"12015550123", :extension=>nil,
    #   #     :isdn_subaddress=>nil, :phone_context=>nil, :params=>[]}
    #
    # For a local number the dial_string is nil unless the phone-context
    # is a global number prefix, in which case it is the concatenation
    # of the context digits and the local digits. The geographic region
    # of a local number is never guessed.
    #
    # Raises URI::InvalidURIError when the URI is not #usable? because of
    # an unrecognized required parameter.
    def to_dial
      unless usable?
        raise InvalidURIError,
          "cannot dial #{self} (unrecognized required parameter(s): " \
          "#{@unusable_params.join(', ')})"
      end

      digits = number_digits
      context = phone_context
      context_digits = global_context? ? strip_visual_separators(context).sub(/\A\+/, '') : nil

      {
        scheme: 'tel',
        global: global?,
        number: digits,
        dial_string:
          if global?
            digits.sub(/\A\+/, '')
          else
            context_digits && context_digits + digits
          end,
        extension: extension,
        isdn_subaddress: isdn_subaddress,
        phone_context: context,
        params: normalized_params,
      }
    end

    # Canonical representation of the URI: the scheme is lowercase,
    # visual separators are removed from the subscriber number,
    # parameter names are lowercased and parameters are sorted (with
    # +ext+ last, as required by RFC 3966).
    def normalize
      uri = dup
      uri.normalize!
      uri
    end

    # Destructive version of #normalize.
    def normalize!
      @number = canonical_number
      @params = canonical_params.map { |name, value| [name, value] }
      set_opaque(self.to_s.sub(/\Atel:/, ''))
      self
    end

    # Semantic comparison per RFC 3966 section 4.
    #
    # Visual separators and parameter order are ignored; parameter name
    # case and the isub value case are ignored, while other parameter
    # values are compared case-sensitively. A local number whose
    # phone-context is a global number prefix is equal to the global
    # number formed by concatenating the context and the local digits.
    def ==(oth)
      return false unless oth.is_a?(Tel)

      a = comparison_form
      b = oth.send(:comparison_form)
      a[:kind] == b[:kind] &&
        a[:digits] == b[:digits] &&
        a[:params] == b[:params]
    end

    # Returns the hash value consistent with #==.
    def hash
      comparison_form.hash
    end

    def eql?(oth) # :nodoc:
      self.class == oth.class && self == oth
    end

    # Reconstructs the URI from its components.
    def to_s
      str = 'tel:'.dup
      str << @number
      @params.each do |name, value|
        str << ';' << name
        str << '=' << value if value
      end
      str
    end
    alias to_str to_s

    private

    def parse_opaque(opaque)
      parts = opaque.split(';', -1)
      number = parts.first
      if number.nil? || number.empty?
        raise InvalidComponentError,
          "missing telephone number in tel URL: #{opaque}"
      end

      @global_number = number.start_with?('+')
      check_number(number)
      @number = number

      parse_params(parts.length > 1 ? parts[1..-1] : [])
      check_param_constraints
      true
    end

    def check_number(number)
      regexp = @global_number ? GLOBAL_NUMBER_DIGITS : LOCAL_NUMBER_DIGITS
      if regexp !~ number
        raise InvalidComponentError,
          "bad telephone number in tel URL: #{number}"
      end
      true
    end

    def parse_params(raw_params)
      @params = []
      seen = Hash.new(0)
      raw_params.each do |raw|
        name, value = raw.split('=', 2)
        check_param_syntax(name, value)
        canonical = canonical_param_name(name)
        seen[canonical] += 1
        @params << [name, value]
      end

      ext_indexes = @params.each_index.select { |i|
        canonical_param_name(@params[i][0]) == 'ext'
      }
      if ext_indexes.length > 1
        raise InvalidComponentError,
          "multiple ext parameters in tel URL"
      end
      if (i = ext_indexes.first) && i != @params.length - 1
        raise InvalidComponentError,
          "ext parameter must be the last parameter in tel URL"
      end

      %w[isub phone-context].each do |single|
        if seen[single] > 1
          raise InvalidComponentError,
            "multiple #{single} parameters in tel URL"
        end
      end

      check_param_values
      @unusable_params = @params.map { |name, _| canonical_param_name(name) }.select { |n|
        n.start_with?('!') && !KNOWN_PARAMS.include?(n)
      }
    end

    def check_param_syntax(name, value)
      if name.nil? || name.empty? || PNAME !~ name
        raise InvalidComponentError,
          "bad parameter name in tel URL: #{name.inspect}"
      end
      if value && PVALUE !~ value
        raise InvalidComponentError,
          "bad value for parameter #{canonical_param_name(name)} in tel URL"
      end
    end

    def check_param_values
      @params.each do |name, value|
        case canonical_param_name(name)
        when 'isub'
          if value.nil? || !nonempty_separated?(decode(value), /[0-9A-Fa-f]/)
            raise InvalidComponentError,
              "bad isub value in tel URL: #{value.inspect}"
          end
        when 'ext'
          if value.nil? || !nonempty_separated?(decode(value), /[0-9]/)
            raise InvalidComponentError,
              "bad ext value in tel URL: #{value.inspect}"
          end
        when 'phone-context'
          if value.nil? || !valid_phone_context?(decode(value))
            raise InvalidComponentError,
              "bad phone-context value in tel URL: #{value.inspect}"
          end
        end
      end
    end

    def check_param_constraints
      names = @params.map { |name, _| canonical_param_name(name) }
      if names.include?('isub') && names.include?('ext')
        raise InvalidComponentError,
          "isub and ext parameters must not appear together in tel URL"
      end
      if local? && !names.include?('phone-context')
        raise InvalidComponentError,
          "local number in tel URL requires a phone-context parameter: #{@number}"
      end
    end

    # Validates 1*(visual-separator / <digits>) as restricted by
    # RFC 3966 5.1.1: separators may only appear between digits, so
    # leading, trailing and doubled separators are rejected.
    def nonempty_separated?(value, digit)
      return false if value.empty?
      return false if value =~ /\A[.()\-]/ || value =~ /[.()\-]\z/
      return false if value =~ /[.()\-]{2}/

      value.each_char.all? { |c| c =~ /[.()\-]/ || c =~ digit } &&
        value =~ digit
    end

    # phone-context = domain-name / global-network-digits / network-prefix
    # network-prefix = "%" 1*(phonedigit / dtmf-digit /
    #                   reserved-visual-separator / "@" / "&" / "+" /
    #                   "$" / ",")
    def valid_phone_context?(value)
      return false if value.empty?
      if value.start_with?('+')
        GLOBAL_NUMBER_PREFIX.match?(value)
      elsif value.start_with?('%')
        value.length > 1 &&
          value[1..-1].each_char.all? { |c|
            c =~ /[0-9*#\-\.\(\)@&+$,]/
          }
      else
        DOMAIN.match?(value.downcase)
      end
    end

    def global_context?
      context = phone_context
      !!(context && context.start_with?('+') && GLOBAL_NUMBER_PREFIX.match?(context))
    end

    def strip_visual_separators(value)
      value.delete('-.()')
    end

    def decode(value)
      URI.decode_uri_component(value)
    rescue ArgumentError
      raise InvalidComponentError,
        "invalid percent-encoding in tel URL: #{value}"
    end

    def canonical_param_name(name)
      decode(name.to_s).downcase
    end

    # Normalized subscriber number for comparison and canonicalization.
    def canonical_number
      digits = strip_visual_separators(@number)
      if local?
        digits.upcase
      else
        digits
      end
    end

    # Reduces the URI to its RFC 3966 section 4 comparison form. A local
    # number with a global phone-context is expanded into that global
    # number; other local numbers remain local.
    def comparison_form
      if global?
        {
          kind: :global,
          digits: canonical_number,
          params: normalized_param_multiset,
        }
      else
        context = phone_context
        if context && context.start_with?('+') &&
            GLOBAL_NUMBER_PREFIX.match?(context)
          {
            kind: :global,
            digits: strip_visual_separators(context) + canonical_number,
            params: params_without_context,
          }
        else
          {
            kind: :local,
            digits: canonical_number,
            params: normalized_param_multiset,
          }
        end
      end
    end

    def params_without_context
      normalized_param_multiset.reject { |name, _| name == 'phone-context' }
    end

    # Array of [name, value] pairs with percent escapes decoded and
    # RFC 3966 comparison rules applied. Parameter order is preserved;
    # use #normalized_param_multiset for order-insensitive comparison.
    def normalized_params
      @params.map do |name, raw_value|
        cname = canonical_param_name(name)
        value = raw_value.nil? ? nil : canonical_param_value(cname, raw_value)
        [cname, value]
      end
    end

    def canonical_param_value(name, raw_value)
      value = decode(raw_value)
      case name
      when 'ext'
        strip_visual_separators(value)
      when 'isub'
        strip_visual_separators(value).upcase
      when 'phone-context'
        canonical_phone_context(value)
      else
        value
      end
    end

    def canonical_phone_context(value)
      if value.start_with?('+')
        strip_visual_separators(value)
      elsif value.include?('.') && DOMAIN.match?(value.downcase)
        value.downcase
      else
        value
      end
    end

    def normalized_param_multiset
      normalized_params.sort_by { |name, value|
        ext = name == 'ext' ? 1 : 0
        [ext, name, value || '']
      }
    end

    def canonical_params
      normalized_params.sort_by { |name, _|
        name == 'ext' ? 1 : 0
      }
    end

    # Normalizes the three accepted forms of a build argument into an
    # Array of [name, value] pairs.
    def self.params_from(params)
      return [] if params.nil?

      case params
      when Array
        params.map do |pair|
          if pair.is_a?(Array)
            [pair[0].to_s, pair[1] && pair[1].to_s]
          else
            [pair.to_s, nil]
          end
        end
      when Hash
        params.map { |name, value| [name.to_s, value && value.to_s] }
      when String
        params.split(';', -1).reject(&:empty?).map do |raw|
          name, value = raw.split('=', 2)
          [name, value]
        end
      else
        raise ArgumentError,
          "bad params (expected String, Array or Hash): #{params.inspect}"
      end
    end

  end

  register_scheme 'TEL', Tel
end
