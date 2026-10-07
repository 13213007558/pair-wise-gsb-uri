# frozen_string_literal: false
require 'test/unit'
require 'uri'

class URI::TestURN < Test::Unit::TestCase
  def test_parse_components
    urn = URI.parse('URN:Example:a?+resolver=example?+2?=profile=one#part')

    assert_instance_of(URI::URN, urn)
    assert_equal('urn', urn.scheme)
    assert_equal('example', urn.nid)
    assert_equal('a', urn.nss)
    assert_equal('resolver=example?+2', urn.r_component)
    assert_equal('profile=one', urn.q_component)
    assert_equal('part', urn.fragment)
    assert_equal('urn:example:a?+resolver=example?+2?=profile=one#part', urn.to_s)
    assert_equal('example:a', urn.opaque)
    assert_nil(urn.query)
    assert_nil(urn.path)
    refute_predicate(urn, :hierarchical?)
  end

  def test_parse_q_component_without_r_component
    urn = URI.parse('urn:example:a?=profile=one')

    assert_equal('a', urn.nss)
    assert_nil(urn.r_component)
    assert_equal('profile=one', urn.q_component)
    assert_equal('urn:example:a?=profile=one', urn.to_s)
  end

  def test_empty_fragment_is_present
    urn = URI.parse('urn:example:a#')

    assert_equal('', urn.fragment)
    assert_equal('urn:example:a#', urn.to_s)
  end

  def test_split_components
    assert_equal(
      ['example', 'a', 'resolver', 'profile', 'part'],
      URI::URN.split('urn:example:a?+resolver?=profile#part')
    )
  end

  def test_build
    urn = URI::URN.build(
      nid: 'example',
      nss: 'a',
      r_component: 'resolver',
      q_component: 'profile',
      fragment: 'part'
    )

    assert_equal('urn:example:a?+resolver?=profile#part', urn.to_s)
  end

  def test_rfc2396_parser_also_returns_urn
    urn = URI::RFC2396_PARSER.parse('urn:example:a?+r?=q')

    assert_instance_of(URI::URN, urn)
    assert_equal('r', urn.r_component)
    assert_equal('q', urn.q_component)
  end

  def test_syntactic_equivalence_ignores_r_q_and_fragment
    base = URI.parse('urn:example:resource')
    with_r = URI.parse('urn:example:resource?+resolver=one')
    with_q = URI.parse('urn:example:resource?=profile=one')
    with_r_and_q = URI.parse('urn:example:resource?+resolver=one?=profile=one#part')

    assert(base.syntactic_equivalent?(with_r))
    assert(base.syntactic_equivalent?(with_q))
    assert(base.syntactic_equivalent?(with_r_and_q))
    refute(base == with_r)
    refute(base == with_q)
    refute(with_r == with_q)
  end

  def test_same_nss_with_different_resolution_components
    base = URI.parse('urn:example:resource')
    with_r = URI.parse('urn:example:resource?+resolver=one')
    with_q = URI.parse('urn:example:resource?=profile=one')

    assert(base.syntactic_equivalent?(with_r))
    assert(base.syntactic_equivalent?(with_q))
    assert_raise(URI::URN::MissingNamespacePolicyError) do
      base.namespace_specific_equivalent?(with_r)
    end

    base.register_namespace_specific_policy(lambda { |left, right| left.syntactic_equivalent?(right) })
    assert(base.namespace_specific_equivalent?(with_r))
    assert(base.namespace_specific_equivalent?(with_q))
  end

  def test_syntactic_equivalence_normalizes_only_allowed_percent_encoding
    tilde = URI.parse('urn:example:a%7eb')
    slash = URI.parse('urn:example:a%2fb')

    assert(tilde.syntactic_equivalent?(URI.parse('urn:example:a~b')))
    assert(slash.syntactic_equivalent?(URI.parse('urn:example:a%2Fb')))
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:a/b') }
    assert_equal('urn:example:a~b', tilde.normalize.to_s)
    assert_equal('urn:example:a%2Fb', slash.normalize.to_s)
  end

  def test_namespace_specific_equivalence_requires_policy
    urn = URI.parse('urn:isbn:0-123-45678-9')
    other = URI.parse('urn:isbn:0123456789?+resolver=one')

    assert_raise(URI::URN::MissingNamespacePolicyError) do
      urn.namespace_specific_equivalent?(other)
    end
  end

  def test_namespace_specific_equivalence_uses_instance_policy
    urn = URI.parse('urn:isbn:0-123-45678-9')
    other = URI.parse('urn:isbn:0123456789?+resolver=one')
    received = nil
    urn.namespace_specific_policy = lambda do |left, right|
      received = [left.nss, right.nss]
      left.nss.delete('-') == right.nss
    end

    assert(urn.namespace_specific_equivalent?(other))
    assert_equal(['0-123-45678-9', '0123456789'], received)
  end

  def test_namespace_specific_equivalence_does_not_guess_other_namespace
    urn = URI.parse('urn:isbn:0-123-45678-9')
    other = URI.parse('urn:other:a')
    called = false
    urn.namespace_specific_policy = lambda { called = true }

    refute(urn.namespace_specific_equivalent?(other))
    refute(called)
  end

  def test_namespace_specific_policy_must_be_callable
    assert_raise(ArgumentError) do
      URI::URN.new('urn', 'example', 'a', nil, nil, nil, URI::DEFAULT_PARSER,
                  namespace_specific_policy: :not_callable)
    end
  end

  def test_q_component_before_r_component_is_rejected
    assert_raise(URI::InvalidURIError) do
      URI.parse('urn:example:a?=profile?+resolver')
    end
  end

  def test_setting_r_component_after_q_component_is_rejected
    urn = URI.parse('urn:example:a?=profile')

    assert_raise(URI::InvalidComponentError) do
      urn.r_component = 'resolver'
    end
  end

  def test_invalid_components
    assert_raise(URI::InvalidURIError) { URI.parse('urn:x:a') }
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:') }
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:a?+') }
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:a?=') }
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:a%XX') }
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:a/b') }
    assert_raise(URI::InvalidURIError) { URI.parse('urn:example:a?') }
  end

  def test_formal_nid
    assert_instance_of(URI::URN, URI.parse('urn:urn-1:a'))
  end
end
