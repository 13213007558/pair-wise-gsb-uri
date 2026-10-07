# frozen_string_literal: false
# = uri/tel.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'generic'

module URI

  #
  # RFC3966, the tel URI scheme.
  #
  class TEL < Generic
    include RFC2396_REGEXP

    # A Default port of nil for URI::TEL.
    DEFAULT_PORT = nil

    # An Array of the available components for URI::TEL.
    COMPONENT = [ :scheme, :number, :parameters ].freeze

    # :stopdoc:
    #  RFC 3966, Section 3. URI Syntax:
    #
    #  telephone-uri        = "tel:" telephone-subscriber
    #  telephone-subscriber = global-number / local-number
    #  global-number        = global-number-digits *par
    #  local-number         = local-number-digits *par context *par
    #  par                  = parameter / extension / isdn-subaddress
    #  isdn-subaddress      = ";isub=" 1*phonedigit
    #  extension            = ";ext=" 1*phonedigit
    #  context              = ";phone-context=" descriptor
    #  descriptor           = domainname / global-number-digits
    #  global-number-digits = "+" *phonedigit DIGIT *phonedigit
    #  local-number-digits  =
    #     *phonedigit-hex (HEXDIG / "*" / "#") *phonedigit-hex
    #  domainname   = *( domainlabel "." ) toplabel [ "." ]
    #  domainlabel  = alphanum / alphanum *( alphanum / "-" ) alphanum
    #  toplabel     = ALPHA / ALPHA *( alphanum / "-" ) alphanum
    #  parameter    = ";" pname ["=" pvalue ]
    #  pname        = 1*( alphanum / "-" )
    #  pvalue       = 1*paramchar
    #  paramchar    = param-unreserved / unreserved / pct-encoded
    #  unreserved   = alphanum / mark
    #  mark         = "-" / "_" / "." / "!" / "~" / "*" / "'" / "(" / ")"
    #  param-unreserved = "[" / "]" / "/" / ":" / "&" / "+" / "$"
    #  phonedigit   = DIGIT / [ visual-separator ]
    #  visual-separator = "-" / "." / "(" / ")"
    #  phonedigit-hex = HEXDIG / "*" / "#" / [ visual-separator ]
    #  alphanum     = ALPHA / DIGIT

    # Visual separators of a phone number; they carry no meaning and
    # are ignored when comparing numbers (RFC 3966, Section 5).
    VISUAL_SEPARATOR = "-.()".freeze

    # global-number-digits = "+" *phonedigit DIGIT *phonedigit
    GLOBAL_NUMBER_REGEXP = /\A\+[0-9\-.()]*[0-9][0-9\-.()]*\z/
    # local-number-digits = *phonedigit-hex (HEXDIG / "*" / "#") *phonedigit-hex
    LOCAL_NUMBER_REGEXP  = /\A[0-9A-Fa-f*#\-.()]*[0-9A-Fa-f*#][0-9A-Fa-f*#\-.()]*\z/
    # 1*phonedigit, the value of the "ext" and "isub" parameters
    PHONEDIGIT_REGEXP = /\A[0-9\-.()]+\z/
    # pname = 1*( alphanum / "-" )
    PNAME_REGEXP = /\A[0-9A-Za-z-]+\z/
    # pvalue = 1*paramchar
    PVALUE_REGEXP = /\A(?:%\h\h|[0-9A-Za-z\-_.!~*'()\[\]\/:&+$])+\z/
    # domainlabel = alphanum / alphanum *( alphanum / "-" ) alphanum
    DOMAINLABEL = /[0-9A-Za-z](?:[0-9A-Za-z-]*[0-9A-Za-z])?/
    # toplabel = ALPHA / ALPHA *( alphanum / "-" ) alphanum
    TOPLABEL = /[A-Za-z](?:[0-9A-Za-z-]*[0-9A-Za-z])?/
    # domainname = *( domainlabel "." ) toplabel [ "." ]
    DOMAINNAME_REGEXP = /\A(?:#{DOMAINLABEL}\.)*#{TOPLABEL}\.?\z/

    # Parameter names defined by RFC 3966.
    KNOWN_PARAMETERS = %w[ext isub phone-context].freeze
    # :startdoc:

    #
    # == Description
    #
    # Creates a new URI::TEL object from components, with syntax checking.
    #
    # Components can be provided as an Array or Hash. If an Array is used,
    # the components must be supplied as <code>[number, parameters]</code>.
    #
    # If a Hash is used, the keys are the component names preceded by colons.
    #
    # The parameters can be supplied as an Array of Arrays like
    # <code>[['ext', '123']]</code>, as an Array of pre-encoded Strings
    # like <code>['ext=123']</code>, or as a Hash like
    # <code>{'ext' => '123'}</code>.
    #
    # Examples:
    #
    #    require 'uri'
    #
    #    t1 = URI::TEL.build(['+1-201-555-0123'])
    #    t1.to_s  # => "tel:+1-201-555-0123"
    #
    #    t2 = URI::TEL.build(['7042', [['phone-context', 'example.com']]])
    #    t2.to_s  # => "tel:7042;phone-context=example.com"
    #
    #    t3 = URI::TEL.build({:number => '+1-201-555-0123', :parameters => [['ext', '123']]})
    #    t3.to_s  # => "tel:+1-201-555-0123;ext=123"
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)

      case tmp[:number]
      when String
        tmp[:opaque] = tmp[:number].dup
      when nil
        tmp[:opaque] = ''
      else
        tmp[:opaque] = tmp[:number].to_s
      end

      params =
        case tmp[:parameters]
        when Array
          tmp[:parameters].collect { |x|
            if x.kind_of?(Array)
              x[1] ? x[0].to_s + '=' + x[1].to_s : x[0].to_s
            else
              x.to_s
            end
          }
        when Hash
          tmp[:parameters].collect { |h, v|
            v ? h.to_s + '=' + v.to_s : h.to_s
          }
        when nil
          []
        else
          [tmp[:parameters].to_s]
        end
      params.each do |param|
        tmp[:opaque] << ';' << param
      end

      super(tmp)
    end

    #
    # == Description
    #
    # Creates a new URI::TEL object from generic URI components with
    # no syntax checking.
    #
    # This method is usually called from URI::parse, which checks
    # the validity of each component.
    #
    def initialize(*arg)
      super(*arg)

      @number = nil
      @parameters = []

      unless @opaque
        raise InvalidComponentError,
          "missing opaque part for tel URI"
      end

      number, *params = @opaque.split(';', -1)
      pairs = params.collect { |param| split_parameter(param) }

      check_number(number)
      pairs.each do |name, value|
        check_parameter(name, value)
      end
      check_subscriber(number, pairs)

      set_number(number)
      set_parameters(pairs)
    end

    # The phone number of the URI, as a String, including any visual
    # separators.  A global number starts with "+".
    attr_reader :number

    # The parameters of the URI, as an Array of [name, value] pairs.
    # The value is nil for a parameter without a value.
    attr_reader :parameters

    # Checks the number +v+ component.
    def check_number(v)
      unless v && (GLOBAL_NUMBER_REGEXP =~ v || LOCAL_NUMBER_REGEXP =~ v)
        raise InvalidComponentError,
          "bad number component for tel URI: #{v}"
      end

      true
    end
    private :check_number

    # Private setter for number +v+.
    def set_number(v)
      @number = v
    end
    protected :set_number

    # Setter for number +v+ (with validation).
    def number=(v)
      check_number(v)
      check_subscriber(v, @parameters)
      set_number(v)
      v
    end

    # Checks a single parameter name and value.
    def check_parameter(name, value)
      if PNAME_REGEXP !~ name
        raise InvalidComponentError,
          "bad parameter name for tel URI: #{name}"
      end

      case name.downcase
      when 'ext', 'isub'
        if value.nil? || PHONEDIGIT_REGEXP !~ value
          raise InvalidComponentError,
            "bad '#{name}' parameter value for tel URI: #{value}"
        end
      when 'phone-context'
        if value.nil? ||
            (GLOBAL_NUMBER_REGEXP !~ value && DOMAINNAME_REGEXP !~ value)
          raise InvalidComponentError,
            "bad 'phone-context' parameter value for tel URI: #{value}"
        end
      else
        if value && PVALUE_REGEXP !~ value
          raise InvalidComponentError,
            "bad parameter value for tel URI: #{value}"
        end
      end

      true
    end
    private :check_parameter

    # Private setter for parameters +v+.
    def set_parameters(v)
      @parameters = v
    end
    protected :set_parameters

    # Setter for parameters +v+ (with validation).
    #
    # Accepts an Array of [name, value] pairs, an Array of pre-encoded
    # Strings ("name" or "name=value"), or a Hash.
    def parameters=(v)
      pairs = normalize_parameters(v)
      pairs.each do |name, value|
        check_parameter(name, value)
      end
      check_subscriber(@number, pairs)
      set_parameters(pairs)
      v
    end

    # Returns true if the URI holds a global number, i.e. one starting
    # with "+".
    def global?
      !@number.nil? && @number.start_with?('+')
    end

    # Returns true if the URI holds a local number.  A local number is
    # only valid within the context described by #phone_context.
    def local?
      !global?
    end

    # The value of the "ext" (extension) parameter, or nil.
    def extension
      parameter_value('ext')
    end

    # The value of the "isub" (ISDN subaddress) parameter, or nil.
    def isdn_subaddress
      parameter_value('isub')
    end

    # The value of the "phone-context" parameter, or nil.
    #
    # The phone context describes the scope in which a local number is
    # valid, either as a domain name (e.g. "example.com") or as a global
    # number prefix (e.g. "+1-914-555").  It does not, by itself,
    # identify a country or geographic region.
    def phone_context
      parameter_value('phone-context')
    end

    # Returns an Array of the parameter names that are marked as
    # mandatory (their name starts with "m-") but are not known to this
    # implementation (RFC 3966, Section 4.4).
    def unknown_mandatory_parameters
      @parameters.collect { |name, _| name }.select { |name|
        name.downcase.start_with?('m-') &&
          !KNOWN_PARAMETERS.include?(name.downcase)
      }
    end

    # Returns true if the phone number may be used, i.e. the URI does
    # not carry any unknown mandatory parameters (RFC 3966,
    # Section 4.4: "An implementation MUST NOT use the phone number if
    # it contains unknown mandatory parameters").
    def usable?
      unknown_mandatory_parameters.empty?
    end

    # Constructs String from URI.
    def to_s
      @scheme + ':' +
        if @number
          @number
        else
          ''
        end +
        @parameters.collect { |name, value|
          if value
            ";#{name}=#{value}"
          else
            ";#{name}"
          end
        }.join +
        if @fragment
          '#' + @fragment
        else
          ''
        end
    end

    #
    # Compares two tel URIs semantically, as specified by RFC 3966,
    # Section 5:
    #
    # * both must be either global or local numbers,
    # * the numbers must be equal after removing all visual separators,
    # * each parameter name and value must appear in both URIs;
    #   parameter names are compared case-insensitively, parameter
    #   values are case-sensitive, and the values of "ext" and "isub"
    #   are compared after removing visual separators,
    # * a "phone-context" domain name is compared case-insensitively,
    #   while a "phone-context" global number is compared digit by
    #   digit,
    # * the order of parameters is insignificant.
    #
    def ==(oth)
      self.class == oth.class &&
        comparison_key == oth.comparison_key
    end

    # Returns the hash value.
    def hash
      comparison_key.hash
    end

    # Compares with _oth_ for Hash.
    def eql?(oth)
      self.class == oth.class &&
        comparison_key.eql?(oth.comparison_key)
    end

    # Key used for the semantic comparison of tel URIs
    # (RFC 3966, Section 5).
    def comparison_key # :nodoc:
      [
        global?,
        @number.delete(VISUAL_SEPARATOR),
        @parameters.collect { |name, value|
          canonical_parameter(name, value)
        }.sort_by { |name, value| [name, value ? 1 : 0, value.to_s] }
      ]
    end
    protected :comparison_key

    # Splits a raw parameter string ("name" or "name=value") into a
    # [name, value] pair; the value is nil when absent.
    def split_parameter(param) # :nodoc:
      name, value = param.split('=', 2)
      [name, value]
    end
    private :split_parameter

    # Converts user-supplied parameters into an Array of
    # [name, value] pairs.
    def normalize_parameters(v) # :nodoc:
      case v
      when nil
        []
      when Array
        v.collect { |param|
          if param.kind_of?(Array)
            [param[0].to_s, param[1].nil? ? nil : param[1].to_s]
          else
            split_parameter(param.to_s)
          end
        }
      when Hash
        v.collect { |name, value|
          [name.to_s, value.nil? ? nil : value.to_s]
        }
      else
        [split_parameter(v.to_s)]
      end
    end
    private :normalize_parameters

    # Checks the combination of number and parameters: a local number
    # requires a "phone-context" parameter while a global number
    # forbids it, and "ext" and "isub" must not appear together
    # (RFC 3966, Sections 4.1-4.3).
    def check_subscriber(number, parameters) # :nodoc:
      extension = nil
      isdn_subaddress = nil
      phone_context = nil

      parameters.each do |name, value|
        case name.downcase
        when 'ext'
          if extension
            raise InvalidComponentError,
              "duplicate 'ext' parameter for tel URI"
          end
          extension = value
        when 'isub'
          if isdn_subaddress
            raise InvalidComponentError,
              "duplicate 'isub' parameter for tel URI"
          end
          isdn_subaddress = value
        when 'phone-context'
          if phone_context
            raise InvalidComponentError,
              "duplicate 'phone-context' parameter for tel URI"
          end
          phone_context = value
        end
      end

      if extension && isdn_subaddress
        raise InvalidComponentError,
          "tel URI cannot contain both 'ext' and 'isub' parameters"
      end

      if number&.start_with?('+')
        if phone_context
          raise InvalidComponentError,
            "global number for tel URI cannot have a 'phone-context' parameter: #{number}"
        end
      elsif number && !phone_context
        raise InvalidComponentError,
          "local number for tel URI requires a 'phone-context' parameter: #{number}"
      end

      true
    end
    private :check_subscriber

    # Returns the value of the parameter +name+ (matched
    # case-insensitively), or nil.
    def parameter_value(name) # :nodoc:
      pair = @parameters.find { |pname, _| pname.downcase == name }
      pair && pair[1]
    end
    private :parameter_value

    # Canonicalizes a parameter for comparison: names are
    # case-insensitive, values are case-sensitive, except that "ext"
    # and "isub" values ignore visual separators and "phone-context"
    # is compared per its descriptor form (RFC 3966, Section 5).
    def canonical_parameter(name, value) # :nodoc:
      name = name.downcase
      case name
      when 'ext', 'isub'
        value = value.delete(VISUAL_SEPARATOR) if value
      when 'phone-context'
        value = canonical_descriptor(value)
      end
      [name, value]
    end
    private :canonical_parameter

    # Canonicalizes a "phone-context" descriptor: a domain name is
    # compared case-insensitively, a global number digit by digit.
    def canonical_descriptor(value) # :nodoc:
      if value.start_with?('+')
        value.delete(VISUAL_SEPARATOR)
      else
        value.downcase
      end
    end
    private :canonical_descriptor
  end

  register_scheme 'TEL', TEL
end
