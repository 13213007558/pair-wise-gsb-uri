# frozen_string_literal: false
# = uri/urn.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'generic'

module URI

  #
  # RFC8141, the urn scheme (Uniform Resource Name).
  #
  # A URN names a resource without implying its location or how to
  # access it:
  #
  #   require 'uri'
  #
  #   urn = URI.parse('urn:example:foo?+rResolve?=qQuery#frag')
  #   # => #<URI::URN urn:example:foo?+rResolve?=qQuery#frag>
  #   urn.scheme       # => "urn"
  #   urn.nid          # => "example"
  #   urn.nss          # => "foo"
  #   urn.r_component  # => "rResolve"
  #   urn.q_component  # => "qQuery"
  #   urn.fragment     # => "frag"
  #
  # The generic URI components cannot express the boundaries of a URN,
  # so URI::URN exposes them directly as #nid, #nss, #r_component,
  # #q_component and #fragment, per the RFC 8141 grammar:
  #
  #   namestring    = assigned-name [ rq-components ] [ "#" f-component ]
  #   assigned-name = "urn" ":" NID ":" NSS
  #   rq-components = [ "?+" r-component ] [ "?=" q-component ]
  #
  # The r-component must precede the q-component; a namestring with the
  # wrong order is rejected.
  #
  # == Equivalence
  #
  # Two URNs can be compared at three distinct levels:
  #
  # #==::                    Full equivalence: every component, including
  #                          the r-component, q-component and fragment, is
  #                          equal after normalization.
  # #syntax_equivalent?::    Syntax equivalence ("syn-equivalent" in
  #                          RFC 8141): only the assigned-name
  #                          ("urn:NID:NSS") is compared, after case
  #                          normalization of the scheme and NID and
  #                          percent-encoding normalization of the NSS.
  #                          The r/q-components and fragment are ignored.
  # #namespace_equivalent?:: Namespace-specific equivalence: delegated to
  #                          the #equivalence_policy of the instance, or to
  #                          the policy registered for its NID with
  #                          URI::URN.register_equivalence. Raises
  #                          URI::URN::EquivalenceError when no policy is
  #                          available, rather than guessing.
  #
  # Example with the same NSS but different r/q-components:
  #
  #   a = URI.parse('urn:example:foo?+r1?=q1')
  #   b = URI.parse('urn:example:foo?+r2?=q2')
  #   a == b                  # => false
  #   a.syntax_equivalent?(b) # => true
  #
  class URN < Generic
    # A Default port of nil for URI::URN.
    DEFAULT_PORT = nil

    # An Array of the available components for URI::URN.
    COMPONENT = [
      :scheme,
      :nid,
      :nss,
      :r_component,
      :q_component,
      :fragment
    ].freeze

    # :stopdoc:
    #  RFC 8141 grammar:
    #
    #  namestring    = assigned-name [ rq-components ] [ "#" f-component ]
    #  assigned-name = "urn" ":" NID ":" NSS
    #  NID           = (alphanum) 0*30(ldh) (alphanum)
    #  ldh           = alphanum / "-"
    #  NSS           = pchar *(pchar / "/")
    #  rq-components = [ "?+" r-component ] [ "?=" q-component ]
    #  r-component   = pchar *( pchar / "/" / "?" )
    #  q-component   = pchar *( pchar / "/" / "?" )
    #  f-component   = fragment
    #
    #  ; RFC3986
    #  pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
    #  unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
    #  sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
    #  pct-encoded   = "%" HEXDIG HEXDIG
    #  fragment      = *( pchar / "/" / "?" )

    PCHAR = /(?:%\h\h|[A-Za-z0-9\-._~!$&'()*+,;=:@])/.source

    NID_REGEXP = /\A[A-Za-z0-9][A-Za-z0-9-]{0,30}[A-Za-z0-9]\z/
    NSS_REGEXP = /\A#{PCHAR}(?:#{PCHAR}|\/)*\z/
    RQ_REGEXP  = /\A(?:#{PCHAR}|[\/\?])+\z/

    # Characters allowed to appear literally (unencoded) in each
    # component.  A percent-encoded sequence is decoded during
    # normalization only when it stands for one of these; any other
    # sequence is kept encoded, with its hex digits uppercased.
    NSS_DECODABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/".freeze
    RQ_DECODABLE  = (NSS_DECODABLE + "?").freeze
    # :startdoc:

    #
    # Raised when a namespace-specific equivalence comparison is
    # requested but no equivalence policy is available for the NID.
    #
    class EquivalenceError < Error; end

    @equivalence_policies = {}

    #
    # == Description
    #
    # Creates a new URI::URN object from components, with syntax checking.
    #
    # Components can be provided as an Array or Hash. If an Array is used,
    # the components must be supplied as
    # <code>[nid, nss, r_component, q_component, fragment]</code>.
    #
    # If a Hash is used, the keys are the component names preceded by
    # colons; an extra +:equivalence_policy+ entry sets the instance
    # policy used by #namespace_equivalent?.
    #
    # Examples:
    #
    #    require 'uri'
    #
    #    u1 = URI::URN.build(['example', 'foo'])
    #    u1.to_s  # => "urn:example:foo"
    #
    #    u2 = URI::URN.build(nid: 'example', nss: 'foo',
    #                        r_component: 'r1', q_component: 'q1',
    #                        fragment: 'f1')
    #    u2.to_s  # => "urn:example:foo?+r1?=q1#f1"
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)
      policy = tmp.delete(:equivalence_policy)

      opaque = "#{tmp[:nid]}:#{tmp[:nss]}"
      opaque << "?+" << tmp[:r_component].to_s if tmp[:r_component]
      opaque << "?=" << tmp[:q_component].to_s if tmp[:q_component]
      tmp[:opaque] = opaque

      urn = super(tmp)
      urn.equivalence_policy = policy if policy
      urn
    end

    #
    # == Description
    #
    # Creates a new URI::URN object from generic URI components with
    # no syntax checking.
    #
    # This method is usually called from URI::parse, which checks
    # the validity of each component.
    #
    def initialize(*arg)
      super(*arg)

      @nid = nil
      @nss = nil
      @r_component = nil
      @q_component = nil
      @equivalence_policy = nil

      unless @opaque
        raise InvalidComponentError,
          "missing opaque part for URN"
      end

      @nid, @nss, @r_component, @q_component = self.class.split_opaque(@opaque)
    end

    # Returns the NID (Namespace Identifier) component of the URN.
    #
    #   URI.parse('urn:example:foo').nid # => "example"
    #
    attr_reader :nid

    # Returns the NSS (Namespace Specific String) component of the URN.
    #
    #   URI.parse('urn:example:foo').nss # => "foo"
    #
    attr_reader :nss

    # Returns the r-component of the URN (the part introduced by "?+"),
    # or nil when it is absent.
    #
    #   URI.parse('urn:example:foo?+r1').r_component # => "r1"
    #
    attr_reader :r_component

    # Returns the q-component of the URN (the part introduced by "?="),
    # or nil when it is absent.
    #
    #   URI.parse('urn:example:foo?=q1').q_component # => "q1"
    #
    attr_reader :q_component

    # The namespace-specific equivalence policy of this instance: a
    # callable, or an object responding to #equivalent?, taking two
    # normalized URI::URN objects.  Used by #namespace_equivalent?;
    # when nil, the policy registered for the NID with
    # URI::URN.register_equivalence is consulted instead.
    attr_accessor :equivalence_policy

    #
    # Returns the assigned-name of the URN, "urn:NID:NSS", which is the
    # only part considered by #syntax_equivalent?.
    #
    #   URI.parse('urn:example:foo?+r?=q#f').assigned_name
    #   # => "urn:example:foo"
    #
    def assigned_name
      "#{@scheme}:#{@nid}:#{@nss}"
    end

    # :stopdoc:
    def self.split_opaque(opaque)
      nid, sep, body = opaque.partition(":")
      if sep.empty?
        raise InvalidComponentError,
          "missing NSS for URN: #{opaque.inspect}"
      end
      check_nid(nid)

      r_index = body.index("?+")
      q_index = body.index("?=")
      if r_index && q_index && r_index > q_index
        raise InvalidComponentError,
          "r-component (?+) must precede q-component (?=): #{opaque.inspect}"
      end

      boundary = [r_index, q_index].compact.min
      nss = boundary ? body[0...boundary] : body
      r_component = r_index ? body[(r_index + 2)...(q_index || body.length)] : nil
      q_component = q_index ? body[(q_index + 2)..-1] : nil

      check_nss(nss)
      check_rq_component(r_component, "r-component") if r_component
      check_rq_component(q_component, "q-component") if q_component

      [nid, nss, r_component, q_component]
    end

    def self.check_nid(nid)
      unless nid =~ NID_REGEXP
        raise InvalidComponentError,
          "invalid NID for URN: #{nid.inspect}"
      end
      true
    end

    def self.check_nss(nss)
      if nss.nil? || nss.empty?
        raise InvalidComponentError,
          "missing NSS for URN"
      end
      unless nss =~ NSS_REGEXP
        raise InvalidComponentError,
          "invalid NSS for URN: #{nss.inspect}"
      end
      true
    end

    def self.check_rq_component(component, name)
      unless component =~ RQ_REGEXP
        raise InvalidComponentError,
          "invalid #{name} for URN: #{component.inspect}"
      end
      true
    end

    def self.normalize_pct_encoding(component, decodable)
      component.gsub(/%\h\h/) do |match|
        decoded = match[1, 2].hex.chr
        if decodable.include?(decoded)
          decoded
        else
          "%#{match[1, 2].upcase}"
        end
      end
    end
    # :startdoc:

    #
    # Returns the canonical form of the NSS +nss+ per RFC 8141:
    # percent-encoded sequences standing for characters allowed
    # unencoded in the NSS are decoded, any other sequence is kept
    # encoded with uppercase hex digits.  Letter case is preserved.
    #
    def self.normalize_nss(nss)
      normalize_pct_encoding(nss, NSS_DECODABLE)
    end

    #
    # Returns the canonical form of the r-component, q-component or
    # f-component +component+ per RFC 8141; see URI::URN.normalize_nss.
    #
    def self.normalize_rq_component(component)
      normalize_pct_encoding(component, RQ_DECODABLE)
    end

    #
    # Registers +policy+ as the namespace-specific equivalence policy
    # for the NID +nid+ (case-insensitive).  The policy is either a
    # callable (or block) taking two normalized URI::URN objects, or an
    # object responding to #equivalent?.
    #
    #   URI::URN.register_equivalence('isbn') do |a, b|
    #     a.nss.delete('-') == b.nss.delete('-')
    #   end
    #   x = URI.parse('urn:isbn:0-201-63361-2')
    #   y = URI.parse('urn:isbn:0201633612')
    #   x.syntax_equivalent?(y)     # => false
    #   x.namespace_equivalent?(y)  # => true
    #
    def self.register_equivalence(nid, policy = nil, &block)
      policy ||= block
      unless policy.respond_to?(:call) || policy.respond_to?(:equivalent?)
        raise ArgumentError,
          "expected a callable or an object responding to #equivalent?"
      end
      nid = nid.to_s
      unless nid =~ NID_REGEXP
        raise ArgumentError, "invalid NID: #{nid.inspect}"
      end
      @equivalence_policies[nid.downcase] = policy
    end

    #
    # Removes the namespace-specific equivalence policy registered for
    # the NID +nid+, if any.
    #
    def self.unregister_equivalence(nid)
      @equivalence_policies.delete(nid.to_s.downcase)
    end

    # Returns the policy registered for +nid+, or nil.  See
    # URI::URN.register_equivalence.
    def self.equivalence_policy_for(nid)
      @equivalence_policies[nid.to_s.downcase]
    end

    #
    # Checks the NID +v+ and replaces the NID component.
    #
    def nid=(v)
      self.class.check_nid(v)
      @nid = v
      rebuild_opaque
    end

    #
    # Checks the NSS +v+ and replaces the NSS component.
    #
    def nss=(v)
      self.class.check_nss(v)
      @nss = v
      rebuild_opaque
    end

    #
    # Checks the r-component +v+ and replaces the r-component.
    # Use nil to remove it.
    #
    def r_component=(v)
      self.class.check_rq_component(v, "r-component") if v
      @r_component = v
      rebuild_opaque
    end

    #
    # Checks the q-component +v+ and replaces the q-component.
    # Use nil to remove it.
    #
    def q_component=(v)
      self.class.check_rq_component(v, "q-component") if v
      @q_component = v
      rebuild_opaque
    end

    #
    # Normalizes the URN in place per RFC 8141:
    #
    # * the scheme and NID are downcased,
    # * percent-encoded sequences in the NSS, r/q-components and
    #   fragment are decoded only when they stand for a character
    #   allowed unencoded in that component; other sequences are kept
    #   encoded with uppercase hex digits.
    #
    # The NSS letter case is left untouched: it is case-sensitive.
    #
    def normalize!
      if scheme && scheme != scheme.downcase
        set_scheme(scheme.downcase)
      end
      @nid = nid.downcase if @nid
      @nss = self.class.normalize_nss(@nss) if @nss
      @r_component = self.class.normalize_rq_component(@r_component) if @r_component
      @q_component = self.class.normalize_rq_component(@q_component) if @q_component
      @fragment = self.class.normalize_rq_component(@fragment) if @fragment
      rebuild_opaque
      self
    end

    #
    # Returns true when +other+ is syn-equivalent to self per RFC 8141:
    # the assigned-names ("urn:NID:NSS") are compared after case
    # normalization of the scheme and NID and percent-encoding
    # normalization of the NSS.  The r-component, q-component and
    # fragment are not part of the assigned-name and are ignored.
    #
    # +other+ may be a URI::URN or a String.
    #
    #   a = URI.parse('urn:example:foo?+r1?=q1')
    #   b = URI.parse('URN:EXAMPLE:foo?+r2?=q2')
    #   a.syntax_equivalent?(b) # => true
    #   a == b                  # => false
    #
    def syntax_equivalent?(other)
      other = parser.parse(other) if other.is_a?(String)
      return false unless other.is_a?(URN)

      mine = normalize
      theirs = other.normalize
      mine.nid == theirs.nid && mine.nss == theirs.nss
    end

    #
    # Returns true when +other+ is equivalent to self under the
    # namespace-specific rules of this URN's NID.  The comparison is
    # delegated to the #equivalence_policy of this instance, or to the
    # policy registered for the NID with URI::URN.register_equivalence.
    #
    # Both URNs are normalized (see #normalize!) before being handed to
    # the policy.  +other+ may be a URI::URN or a String.
    #
    # Raises URI::URN::EquivalenceError when no policy is available for
    # the NID: equivalence is never guessed.
    #
    def namespace_equivalent?(other)
      other = parser.parse(other) if other.is_a?(String)
      return false unless other.is_a?(URN)

      policy = @equivalence_policy || self.class.equivalence_policy_for(@nid)
      unless policy
        raise EquivalenceError,
          "no namespace-specific equivalence policy registered for NID #{@nid.inspect}"
      end

      mine = normalize
      theirs = other.normalize
      if policy.respond_to?(:call)
        policy.call(mine, theirs)
      else
        policy.equivalent?(mine, theirs)
      end
    end

    private

    def rebuild_opaque # :nodoc:
      opaque = "#{@nid}:#{@nss}"
      opaque << "?+" << @r_component if @r_component
      opaque << "?=" << @q_component if @q_component
      set_opaque(opaque)
    end
  end

  register_scheme 'URN', URN
end
