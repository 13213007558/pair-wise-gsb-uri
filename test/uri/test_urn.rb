# frozen_string_literal: false
require 'test/unit'
require 'uri/urn'

class URI::TestURN < Test::Unit::TestCase
  def teardown
    URI::URN.unregister_equivalence('example')
    URI::URN.unregister_equivalence('isbn')
  end

  def test_parse
    urn = URI.parse('urn:example:foo?+rResolve?=qQuery#frag')
    assert_instance_of(URI::URN, urn)
    assert_equal('urn', urn.scheme)
    assert_equal('example', urn.nid)
    assert_equal('foo', urn.nss)
    assert_equal('rResolve', urn.r_component)
    assert_equal('qQuery', urn.q_component)
    assert_equal('frag', urn.fragment)
    assert_equal('urn:example:foo', urn.assigned_name)
    assert_equal('urn:example:foo?+rResolve?=qQuery#frag', urn.to_s)
  end

  def test_parse_minimal
    urn = URI.parse('urn:example:foo')
    assert_equal('example', urn.nid)
    assert_equal('foo', urn.nss)
    assert_nil(urn.r_component)
    assert_nil(urn.q_component)
    assert_nil(urn.fragment)
    assert_equal('urn:example:foo', urn.to_s)
  end

  def test_parse_r_only_and_q_only
    urn = URI.parse('urn:example:foo?+r1')
    assert_equal('r1', urn.r_component)
    assert_nil(urn.q_component)
    assert_equal('urn:example:foo?+r1', urn.to_s)

    urn = URI.parse('urn:example:foo?=q1')
    assert_nil(urn.r_component)
    assert_equal('q1', urn.q_component)
    assert_equal('urn:example:foo?=q1', urn.to_s)
  end

  def test_component
    assert_equal([:scheme, :nid, :nss, :r_component, :q_component, :fragment],
                 URI::URN.component)
  end

  def test_scheme_registration
    assert_equal(URI::URN, URI.scheme_list['URN'])
  end

  def test_build_hash
    urn = URI::URN.build(nid: 'example', nss: 'foo',
                         r_component: 'r1', q_component: 'q1', fragment: 'f1')
    assert_instance_of(URI::URN, urn)
    assert_equal('urn:example:foo?+r1?=q1#f1', urn.to_s)
  end

  def test_build_array
    urn = URI::URN.build(['example', 'foo', 'r1', 'q1', 'f1'])
    assert_equal('urn:example:foo?+r1?=q1#f1', urn.to_s)

    urn = URI::URN.build(['example', 'foo', nil, nil, nil])
    assert_equal('urn:example:foo', urn.to_s)
  end

  def test_build_invalid
    assert_raise(URI::InvalidComponentError) { URI::URN.build(nid: 'x', nss: 'foo') }
    assert_raise(URI::InvalidComponentError) { URI::URN.build(nid: 'example', nss: '') }
    assert_raise(URI::InvalidComponentError) { URI::URN.build(nid: 'example', nss: 'a b') }
    assert_raise(URI::InvalidComponentError) { URI::URN.build(nid: 'example', nss: 'a%2') }
    assert_raise(URI::InvalidComponentError) { URI::URN.build(nid: 'example', nss: 'foo', r_component: '') }
  end

  def test_invalid_nid
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:a:foo') }
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:-ab:foo') }
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:ab-:foo') }
    assert_raise(URI::InvalidComponentError) { URI.parse("urn:#{'a' * 33}:foo") }
  end

  def test_empty_nss
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example:') }
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example') }
  end

  def test_nss_cannot_contain_question_mark
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example:a?b') }
  end

  def test_rq_order
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example:foo?=q?+r') }

    urn = URI.parse('urn:example:foo?+r?=q')
    assert_equal('r', urn.r_component)
    assert_equal('q', urn.q_component)
  end

  def test_empty_rq_component
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example:foo?+') }
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example:foo?=') }
    assert_raise(URI::InvalidComponentError) { URI.parse('urn:example:foo?+?=q') }
  end

  def test_normalize_case
    urn = URI.parse('URN:EXAMPLE:Foo').normalize
    assert_equal('urn', urn.scheme)
    assert_equal('example', urn.nid)
    assert_equal('Foo', urn.nss) # NSS is case-sensitive
    assert_equal('urn:example:Foo', urn.to_s)
  end

  def test_percent_normalization
    # characters allowed unencoded in the NSS are decoded
    urn = URI.parse('urn:example:%5A%5a').normalize
    assert_equal('ZZ', urn.nss)
    urn = URI.parse('urn:example:a%3Ab%2Fc').normalize
    assert_equal('a:b/c', urn.nss)

    # other sequences stay encoded, hex digits uppercased
    urn = URI.parse('urn:example:a%3fb%25c%23d').normalize
    assert_equal('a%3Fb%25c%23d', urn.nss)
    assert_equal('urn:example:a%3Fb%25c%23d', urn.to_s)

    # "?" and "/" are allowed literally in r/q-components
    urn = URI.parse('urn:example:a?+x%3fy?=p%2fq').normalize
    assert_equal('x?y', urn.r_component)
    assert_equal('p/q', urn.q_component)

    # the fragment follows the same rules
    urn = URI.parse('urn:example:a#x%3fy').normalize
    assert_equal('x?y', urn.fragment)
  end

  def test_syntax_equivalent
    assert(URI.parse('urn:example:foo').syntax_equivalent?(URI.parse('URN:EXAMPLE:foo')))
    assert(URI.parse('urn:example:%41').syntax_equivalent?('urn:example:A'))
    assert(URI.parse('urn:example:a%3Fb').syntax_equivalent?('urn:example:a%3fb'))

    # NSS is case-sensitive
    assert(!URI.parse('urn:example:Foo').syntax_equivalent?('urn:example:foo'))
    # different NSS
    assert(!URI.parse('urn:example:foo').syntax_equivalent?('urn:example:bar'))
    # not a URN
    assert(!URI.parse('urn:example:foo').syntax_equivalent?('http://example.com/'))
  end

  def test_same_nss_different_rq_components
    a = URI.parse('urn:example:foo?+r1?=q1#f1')
    b = URI.parse('urn:example:foo?+r2?=q2#f2')
    c = URI.parse('urn:example:foo')

    assert_not_equal(a, b)
    assert_not_equal(a, c)
    assert(a.syntax_equivalent?(b))
    assert(a.syntax_equivalent?(c))
    assert(b.syntax_equivalent?(c))
  end

  def test_full_equality
    assert_equal(URI.parse('urn:example:foo?+r?=q#f'),
                 URI.parse('URN:EXAMPLE:foo?+r?=q#f'))
    assert_equal(URI.parse('urn:example:%61'), URI.parse('urn:example:a'))
    assert_not_equal(URI.parse('urn:example:foo?=q1'),
                     URI.parse('urn:example:foo?=q2'))
  end

  def test_namespace_equivalent_unregistered
    a = URI.parse('urn:example:foo')
    b = URI.parse('urn:example:foo')
    assert_raise(URI::URN::EquivalenceError) { a.namespace_equivalent?(b) }
  end

  def test_namespace_equivalent_registered
    URI::URN.register_equivalence('isbn') do |x, y|
      x.nss.delete('-') == y.nss.delete('-')
    end

    x = URI.parse('urn:isbn:0-201-63361-2')
    y = URI.parse('urn:isbn:0201633612')
    z = URI.parse('urn:isbn:0201633613')

    assert(!x.syntax_equivalent?(y))
    assert(x.namespace_equivalent?(y))
    assert(!x.namespace_equivalent?(z))
  end

  def test_instance_equivalence_policy
    x = URI.parse('urn:example:ABC')
    y = URI.parse('urn:example:abc')
    x.equivalence_policy = ->(a, b) { a.nss.downcase == b.nss.downcase }
    assert(x.namespace_equivalent?(y))
    assert_raise(URI::URN::EquivalenceError) { y.namespace_equivalent?(x) }
  end

  def test_policy_object
    policy = Object.new
    def policy.equivalent?(a, b)
      a.nss.size == b.nss.size
    end
    URI::URN.register_equivalence('example', policy)
    assert(URI.parse('urn:example:ab').namespace_equivalent?('urn:example:cd'))
    assert(!URI.parse('urn:example:ab').namespace_equivalent?('urn:example:abc'))
  end

  def test_register_equivalence_validation
    assert_raise(ArgumentError) { URI::URN.register_equivalence('example') }
    assert_raise(ArgumentError) { URI::URN.register_equivalence('bad nid') { true } }
  end

  def test_setters
    urn = URI.parse('urn:example:foo')
    urn.nid = 'example2'
    urn.nss = 'bar'
    urn.r_component = 'r1'
    urn.q_component = 'q1'
    assert_equal('urn:example2:bar?+r1?=q1', urn.to_s)

    urn.r_component = nil
    assert_equal('urn:example2:bar?=q1', urn.to_s)

    assert_raise(URI::InvalidComponentError) { urn.nid = 'x' }
    assert_raise(URI::InvalidComponentError) { urn.nss = 'a?b' }
    assert_raise(URI::InvalidComponentError) { urn.q_component = 'q#' }
  end
end
