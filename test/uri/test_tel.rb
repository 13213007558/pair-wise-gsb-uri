# frozen_string_literal: false
require 'test/unit'
require 'uri/tel'

class URI::TestTEL < Test::Unit::TestCase
  def setup
    @u = URI::TEL
  end

  def teardown
  end

  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_build
    ok = []
    bad = []

    # RFC3966, 6. Examples
    # tel:+1-201-555-0123
    ok << ["tel:+1-201-555-0123"]
    ok[-1] << ["+1-201-555-0123", []]
    ok[-1] << {:number => "+1-201-555-0123"}

    # tel:7042;phone-context=example.com
    ok << ["tel:7042;phone-context=example.com"]
    ok[-1] << ["7042", [["phone-context", "example.com"]]]
    ok[-1] << {:number => "7042",
      :parameters => [["phone-context", "example.com"]]}

    # tel:863-1234;phone-context=+1-914-555
    ok << ["tel:863-1234;phone-context=+1-914-555"]
    ok[-1] << ["863-1234", [["phone-context", "+1-914-555"]]]
    ok[-1] << {:number => "863-1234",
      :parameters => {"phone-context" => "+1-914-555"}}

    # tel:+1-201-555-0123;ext=123
    ok << ["tel:+1-201-555-0123;ext=123"]
    ok[-1] << ["+1-201-555-0123", [["ext", "123"]]]
    ok[-1] << {:number => "+1-201-555-0123", :parameters => [["ext", "123"]]}

    # tel:+1-201-555-0123;isub=123
    ok << ["tel:+1-201-555-0123;isub=123"]
    ok[-1] << ["+1-201-555-0123", [["isub", "123"]]]
    ok[-1] << {:number => "+1-201-555-0123", :parameters => "isub=123"}

    # parameter without a value
    ok << ["tel:+1-201-555-0123;my-param"]
    ok[-1] << ["+1-201-555-0123", [["my-param", nil]]]
    ok[-1] << {:number => "+1-201-555-0123", :parameters => {"my-param" => nil}}

    # local number with hex digits and "*"
    ok << ["tel:*23;phone-context=example.com"]
    ok[-1] << ["*23", [["phone-context", "example.com"]]]
    ok[-1] << {:number => "*23", :parameters => [["phone-context", "example.com"]]}

    ok_all = ok.flatten.join("\0")

    # local number without phone-context
    bad << ["7042", []]
    # global number with phone-context
    bad << {:number => "+1-201-555-0123",
      :parameters => [["phone-context", "example.com"]]}
    # both ext and isub
    bad << {:number => "+1-201-555-0123",
      :parameters => [["ext", "1"], ["isub", "2"]]}
    # empty number
    bad << ["", []]
    # bad parameter name
    bad << {:number => "+1-201-555-0123", :parameters => [["my@param", "1"]]}
    # empty parameter value
    bad << {:number => "+1-201-555-0123", :parameters => [["ext", ""]]}

    ok.each do |x|
      assert_equal(x[0], URI.parse(x[0]).to_s)
      assert_equal(x[0], @u.build(x[1]).to_s)
      assert_equal(x[0], @u.build(x[2]).to_s)
    end

    bad.each do |x|
      assert_raise(URI::InvalidURIError) {
        URI.parse(x)
      }
      assert_raise(URI::InvalidComponentError) {
        @u.build(x)
      }
    end

    assert_equal(ok_all, ok.flatten.join("\0"))
  end

  def test_parse
    # RFC3966, 6. Examples
    u = URI.parse('tel:+1-201-555-0123')
    assert_equal(URI::TEL, u.class)
    assert_equal('+1-201-555-0123', u.number)
    assert_equal([], u.parameters)
    assert_equal(true, u.global?)
    assert_equal(false, u.local?)
    assert_nil(u.phone_context)
    assert_nil(u.extension)
    assert_nil(u.isdn_subaddress)

    u = URI.parse('tel:7042;phone-context=example.com')
    assert_equal('7042', u.number)
    assert_equal([["phone-context", "example.com"]], u.parameters)
    assert_equal(false, u.global?)
    assert_equal(true, u.local?)
    assert_equal('example.com', u.phone_context)

    u = URI.parse('tel:863-1234;phone-context=+1-914-555')
    assert_equal('+1-914-555', u.phone_context)

    u = URI.parse('tel:+1-201-555-0123;ext=123')
    assert_equal('123', u.extension)
    assert_equal([["ext", "123"]], u.parameters)

    u = URI.parse('tel:+1-201-555-0123;isub=456')
    assert_equal('456', u.isdn_subaddress)

    # parameter names are case-insensitive
    u = URI.parse('tel:+1-201-555-0123;EXT=123')
    assert_equal('123', u.extension)

    # parameters are preserved in order
    u = URI.parse('tel:+1-201-555-0123;foo=bar;ext=1;baz')
    assert_equal([["foo", "bar"], ["ext", "1"], ["baz", nil]], u.parameters)
    assert_equal('tel:+1-201-555-0123;foo=bar;ext=1;baz', u.to_s)
  end

  def test_parse_bad
    bad = []

    # empty number
    bad << 'tel:'
    # no digit in global number
    bad << 'tel:+'
    bad << 'tel:+-()'
    # letter in global number
    bad << 'tel:+1-201-555-0123x'
    # local number without phone-context
    bad << 'tel:7042'
    # global number with phone-context
    bad << 'tel:+1-201-555-0123;phone-context=example.com'
    # both ext and isub
    bad << 'tel:+1-201-555-0123;ext=1;isub=2'
    # duplicate parameters that may appear at most once
    bad << 'tel:+1-201-555-0123;ext=1;ext=2'
    bad << 'tel:7042;phone-context=example.com;phone-context=example.org'
    # empty parameter values
    bad << 'tel:+1-201-555-0123;ext='
    bad << 'tel:+1-201-555-0123;foo='
    # bad parameter name
    bad << 'tel:+1-201-555-0123;my@param=1'
    bad << 'tel:+1-201-555-0123;=1'
    # bad phone-context
    bad << 'tel:7042;phone-context='
    bad << 'tel:7042;phone-context=555'
    bad << 'tel:7042;phone-context=example..com'
    # bad character in number
    bad << 'tel:+1 201 555 0123'

    bad.each do |x|
      assert_raise(URI::InvalidComponentError, URI::InvalidURIError) {
        URI.parse(x)
      }
    end
  end

  def test_comparison
    # visual separators are insignificant
    assert_equal(URI('tel:+1-201-555-0123'), URI('tel:+1.201.555.0123'))
    assert_equal(URI('tel:+1-201-555-0123'), URI('tel:+1(201)5550123'))
    assert_equal(URI('tel:7042;phone-context=example.com'),
                 URI('tel:70.4-2;phone-context=example.com'))

    # the order of parameters is insignificant
    assert_equal(URI('tel:+1-201-555-0123;ext=123;foo=bar'),
                 URI('tel:+1-201-555-0123;foo=bar;ext=123'))

    # parameter names are case-insensitive
    assert_equal(URI('tel:+1-201-555-0123;EXT=123'),
                 URI('tel:+1-201-555-0123;ext=123'))
    assert_equal(URI('tel:7042;PHONE-CONTEXT=example.com'),
                 URI('tel:7042;phone-context=example.com'))

    # parameter values are case-sensitive
    assert_not_equal(URI('tel:+1-201-555-0123;foo=Bar'),
                     URI('tel:+1-201-555-0123;foo=bar'))

    # a phone-context domain name is case-insensitive
    assert_equal(URI('tel:7042;phone-context=Example.COM'),
                 URI('tel:7042;phone-context=example.com'))

    # a phone-context global number is compared digit by digit
    assert_equal(URI('tel:863-1234;phone-context=+1-914-555'),
                 URI('tel:863-1234;phone-context=+1.914.555'))
    assert_not_equal(URI('tel:863-1234;phone-context=+1-914-555'),
                     URI('tel:863-1234;phone-context=+1-914-556'))

    # ext and isub values ignore visual separators
    assert_equal(URI('tel:+1-201-555-0123;ext=1-23'),
                 URI('tel:+1-201-555-0123;ext=1.23'))

    # a global number is never equal to a local number
    assert_not_equal(URI('tel:+123'),
                     URI('tel:123;phone-context=example.com'))

    # different numbers or parameters are not equal
    assert_not_equal(URI('tel:+1-201-555-0123'), URI('tel:+1-201-555-0124'))
    assert_not_equal(URI('tel:+1-201-555-0123;ext=1'),
                     URI('tel:+1-201-555-0123;ext=2'))
    assert_not_equal(URI('tel:+1-201-555-0123;ext=1'),
                     URI('tel:+1-201-555-0123'))
    assert_not_equal(URI('tel:+1-201-555-0123;foo'),
                     URI('tel:+1-201-555-0123'))

    # equality is consistent with hash and eql?
    a = URI('tel:+1-201-555-0123;ext=1-23')
    b = URI('tel:+1.201.555.0123;EXT=1.23')
    assert_equal(a, b)
    assert_equal(a.hash, b.hash)
    assert_operator(a, :eql?, b)
    assert_equal(1, [a, b].uniq.size)

    # a tel URI is never equal to another URI or a String
    assert_not_equal(URI('tel:+1-201-555-0123'), 'tel:+1-201-555-0123')
    assert_not_equal(URI('tel:+1-201-555-0123'),
                     URI::Generic.build([nil, nil, nil, nil, nil, nil,
                                         '+1-201-555-0123', nil, nil]))
  end

  def test_usable
    # optional unknown parameters do not affect usability
    u = URI('tel:+1-201-555-0123;foo=bar')
    assert_equal(true, u.usable?)
    assert_equal([], u.unknown_mandatory_parameters)

    # unknown mandatory parameters make the number unusable
    u = URI('tel:+1-201-555-0123;m-foo=bar')
    assert_equal(false, u.usable?)
    assert_equal(['m-foo'], u.unknown_mandatory_parameters)

    # the "m-" marker is matched case-insensitively
    u = URI('tel:+1-201-555-0123;M-FOO=bar')
    assert_equal(false, u.usable?)
    assert_equal(['M-FOO'], u.unknown_mandatory_parameters)

    # known parameters are never reported
    u = URI('tel:7042;phone-context=example.com;ext=1')
    assert_equal(true, u.usable?)
  end

  def test_select
    u = URI.parse('tel:+1-201-555-0123;ext=123')
    assert_equal(['tel', '+1-201-555-0123', [['ext', '123']]],
                 u.select(:scheme, :number, :parameters))
    assert_raise(ArgumentError) do
      u.select(:scheme, :host)
    end
  end

  def test_setter
    u = URI.parse('tel:+1-201-555-0123')
    u.number = '+44-20-1234-5678'
    assert_equal('tel:+44-20-1234-5678', u.to_s)

    u.parameters = [['ext', '9']]
    assert_equal('tel:+44-20-1234-5678;ext=9', u.to_s)
    assert_equal('9', u.extension)

    # a global number cannot become a local one without a phone-context
    assert_raise(URI::InvalidComponentError) do
      u.number = '7042'
    end

    # a global number cannot gain a phone-context
    assert_raise(URI::InvalidComponentError) do
      u.parameters = [['phone-context', 'example.com']]
    end

    # a local number keeps its phone-context
    u = URI.parse('tel:7042;phone-context=example.com')
    u.number = '7043'
    assert_equal('tel:7043;phone-context=example.com', u.to_s)
    u.parameters = [['phone-context', 'example.org']]
    assert_equal('tel:7043;phone-context=example.org', u.to_s)

    # a local number cannot lose its phone-context
    assert_raise(URI::InvalidComponentError) do
      u.parameters = []
    end

    # ext and isub cannot be set together
    assert_raise(URI::InvalidComponentError) do
      u.parameters = [['ext', '1'], ['isub', '2']]
    end
  end

  def test_to_s
    u = URI::TEL.build(['+1-201-555-0123', [['ext', '123'], ['foo']]])
    assert_equal('tel:+1-201-555-0123;ext=123;foo', u.to_s)
  end
end
