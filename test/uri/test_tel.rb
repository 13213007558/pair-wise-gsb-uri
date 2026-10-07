# frozen_string_literal: false
require 'test/unit'
require 'uri/tel'

class URI::TestTel < Test::Unit::TestCase
  def setup
    @u = URI::Tel
  end

  def uri_to_ary(uri)
    uri.class.component.collect { |c| uri.send(c) }
  end

  def test_registered
    assert_equal(URI::Tel, URI.scheme_list["TEL"])
    assert_instance_of(URI::Tel, URI("tel:+1-201-555-0123"))
    assert_instance_of(URI::Tel, URI("TEL:+1234"))
    assert_instance_of(URI::Tel, URI::RFC2396_PARSER.parse("tel:+1234"))
  end

  def test_global_number
    uri = URI("tel:+1-201-555-0123")
    assert_equal(true, uri.global?)
    assert_equal(false, uri.local?)
    assert_equal("+1-201-555-0123", uri.number)
    assert_equal("+12015550123", uri.number_digits)
    assert_equal(nil, uri.phone_context)
    assert_equal(nil, uri.extension)
    assert_equal(nil, uri.isdn_subaddress)
  end

  def test_local_number
    uri = URI("tel:7042;phone-context=example.com")
    assert_equal(false, uri.global?)
    assert_equal(true, uri.local?)
    assert_equal("7042", uri.number)
    assert_equal("7042", uri.number_digits)
    assert_equal("example.com", uri.phone_context)
  end

  def test_visual_separators
    assert_equal("+12015550123",
                 URI("tel:+1(201)555.0123").number_digits)

    invalid = [
      "tel:+1--23", "tel:+1..23", "tel:+1()23", "tel:+1-",
      "tel:+1(201).555", "tel:+", "tel:+a", "tel:1234",
    ]
    invalid.each do |str|
      assert_raise(URI::InvalidComponentError, str) { URI(str) }
    end
  end

  def test_visual_separator_between_digits
    valid = ["+1-23", "+1.23", "+1(23", "+1)23", "+1(201)555"]
    valid.each do |digits|
      assert_nothing_raised(digits) do
        URI("tel:#{digits}")
      end
    end
  end

  def test_local_number_digits
    uri = URI("tel:*23p9;phone-context=example.com")
    assert_equal("*23p9", uri.number_digits)
    uri = URI("tel:*23P9W2;phone-context=example.com")
    assert_equal("*23P9W2", uri.number_digits)
    # ";" starts a parameter; a digit-only name is a valueless parameter
    assert_nothing_raised do
      URI("tel:70;42;phone-context=example.com")
    end
    assert_raise(URI::InvalidURIError) do
      URI("tel:70 42;phone-context=example.com")
    end
    assert_raise(URI::InvalidComponentError) do
      URI("tel:A;phone-context=example.com")
    end
  end

  def test_local_pause_wait_case_preserved
    uri = URI("tel:*9p2W3;phone-context=example.com")
    assert_equal("*9p2W3", uri.number_digits)
  end

  def test_required_phone_context
    assert_raise(URI::InvalidComponentError) { URI("tel:7042") }
    assert_nothing_raised do
      URI("tel:7042;phone-context=example.com")
    end
  end

  def test_global_with_phone_context_allowed_as_param
    uri = URI("tel:+1234;phone-context=example.com")
    assert_equal("example.com", uri.phone_context)
    assert_equal(true, uri.global?)
  end

  def test_phone_context_forms
    assert_equal("example.com",
      URI("tel:123;phone-context=example.com").phone_context)
    assert_equal("+1-201",
      URI("tel:123;phone-context=%2B1-201").phone_context)
    assert_equal("%42",
      URI("tel:123;phone-context=%2542").phone_context)
    assert_raise(URI::InvalidComponentError) do
      URI("tel:123;phone-context=bad_domain")
    end
    assert_raise(URI::InvalidComponentError) do
      URI("tel:123;phone-context=example.com;phone-context=x.org")
    end
  end

  def test_extension
    uri = URI("tel:7042;phone-context=example.com;ext=1234")
    assert_equal("1234", uri.extension)
    assert_equal("1234",
      URI("tel:+1234;ext=1-2-3-4").extension)
    assert_equal("+1234", URI("tel:+1234;ext=1-2-3-4").number_digits)
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;ext=1;ext=2") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;ext=1;isub=2") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;isub=2;ext=1") }
    assert_nothing_raised { URI("tel:+1234;foo=x;ext=1") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;ext=1;foo=x") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;ext=") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;ext=1--2") }
  end

  def test_isdn_subaddress
    uri = URI("tel:+1234;isub=1a2B")
    assert_equal("1a2B", uri.isdn_subaddress)
    assert_equal("1a2b",
      URI("tel:+1234;isub=1-a.2b").isdn_subaddress)
    assert_raise(URI::InvalidComponentError) do
      URI("tel:+1234;isub=AB;isub=CD")
    end
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;isub=") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;isub=zz") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;isub=1-") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;isub=-1") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1234;isub=1--2") }
  end

  def test_parameters_preserved
    uri = URI("tel:+1234;foo=Bar;abc=baz;flag")
    assert_equal([["foo", "Bar"], ["abc", "baz"], ["flag", nil]],
                 uri.params)
    assert_equal("Bar", uri.param("FOO"))
    assert_equal(nil, uri.param("flag"))
    assert_equal(nil, uri.param("missing"))
    assert_equal("a;b", URI("tel:+1;foo=a%3Bb").param("foo"))
    assert_equal("a=b", URI("tel:+1;foo=a%3Db").param("foo"))
    assert_raise(URI::InvalidComponentError) { URI("tel:+1;=x") }
    assert_raise(URI::InvalidComponentError) { URI("tel:+1;foo=a;") }
  end

  def test_required_parameter_marks_unusable
    uri = URI("tel:+1234;!newfeature=off")
    assert_equal(["!newfeature"], uri.unusable_params)
    assert_equal(false, uri.usable?)
    assert_raise(URI::InvalidURIError) { uri.to_dial }

    ok = URI("tel:+1234;foo=bar")
    assert_equal([], ok.unusable_params)
    assert_equal(true, ok.usable?)
  end

  def test_to_dial_global
    dial = URI("tel:+1-201-555-0123").to_dial
    expected = {
      scheme: "tel",
      global: true,
      number: "+12015550123",
      dial_string: "12015550123",
      extension: nil,
      isdn_subaddress: nil,
      phone_context: nil,
      params: [],
    }
    assert_equal(expected, dial)
    assert_equal(true, URI("tel:+12015550123").dialable?)
  end

  def test_to_dial_local
    dial = URI("tel:7042;phone-context=example.com").to_dial
    assert_equal(false, dial[:global])
    assert_equal("7042", dial[:number])
    assert_nil(dial[:dial_string])
    assert_equal("example.com", dial[:phone_context])
    assert_equal(false, URI("tel:7042;phone-context=example.com").dialable?)
  end

  def test_to_dial_global_context
    dial = URI("tel:7042;phone-context=%2B1-201").to_dial
    assert_equal("12017042", dial[:dial_string])
    assert_equal(true, URI("tel:7042;phone-context=+1201").dialable?)
  end

  def test_to_dial_private_context_not_guessed
    dial = URI("tel:123;phone-context=%2542").to_dial
    assert_nil(dial[:dial_string])
    assert_equal("%42", dial[:phone_context])
  end

  def test_equality_separators
    assert_equal(URI("tel:+12015550123"),
                 URI("tel:+1(201)555-0123"))
    assert_equal(URI("tel:+12015550123"),
                 URI("TEL:+1-2-0-1-5-5-5-0-1-2-3"))
    refute_equal(URI("tel:+12015550123"), URI("tel:+12015550124"))
  end

  def test_equality_parameter_order
    a = URI("tel:+1234;foo=Bar;abc=baz")
    b = URI("tel:+1234;abc=baz;foo=Bar")
    assert_equal(a, b)
    assert_equal(a.hash, b.hash)
    assert_equal(true, {a => 1}.key?(b))
  end

  def test_equality_parameter_case
    assert_equal(URI("tel:+1234;FOO=bar"), URI("tel:+1234;foo=bar"))
    refute_equal(URI("tel:+1234;foo=bar"), URI("tel:+1234;foo=BAR"))
    assert_equal(URI("tel:+1234;isub=abcd"),
                 URI("tel:+1234;isub=ABCD"))
    assert_equal(URI("tel:123;phone-context=Example.COM"),
                 URI("tel:123;phone-context=example.com"))
  end

  def test_equality_extension_separators
    a = URI("tel:123;phone-context=x.com;ext=12-34")
    b = URI("tel:123;phone-context=x.com;ext=1234")
    assert_equal(a, b)
    assert_equal(a.hash, b.hash)
  end

  def test_equality_pause_case_insensitive
    # The pause/wait characters p/P and w/W are compared ignoring case
    assert_equal(URI("tel:9p2;phone-context=x.com"),
                 URI("tel:9P2;phone-context=x.com"))
  end

  def test_equality_global_context_forms
    assert_equal(URI("tel:123;phone-context=+1-201"),
                 URI("tel:123;phone-context=%2B1201"))
  end

  def test_equality_local_global_expansion
    assert_equal(URI("tel:+12017042"),
                 URI("tel:7042;phone-context=+1201"))
    assert_equal(URI("tel:+12017042;ext=9"),
                 URI("tel:7042;phone-context=+1201;ext=9"))
    # extra parameters break the equality
    refute_equal(URI("tel:+12017042"),
                 URI("tel:7042;phone-context=+1201;foo=x"))
    # non-global contexts do not expand
    refute_equal(URI("tel:+12017042"),
                 URI("tel:7042;phone-context=example.com"))
  end

  def test_equality_different_arity
    refute_equal(URI("tel:+1234"), URI("tel:+1234;foo=bar"))
    refute_equal(URI("tel:+1234"), URI("http://example.com/"))
  end

  def test_normalize
    uri = URI("tel:70-42;FOO=Bar;isub=ab-CD;phone-context=EXAMPLE.com")
    assert_equal("tel:7042;foo=Bar;isub=ABCD;phone-context=example.com",
                 uri.normalize.to_s)
    assert_equal("tel:70-42;FOO=Bar;isub=ab-CD;phone-context=EXAMPLE.com",
                 uri.to_s)
    assert_nothing_raised { uri.normalize! }
  end

  def test_to_s_round_trip
    str = "tel:+1-201-555-0123;foo=Bar"
    assert_equal(str, URI(str).to_s)
    assert_equal(str, URI(str).to_str)
  end

  def test_build_array
    uri = @u.build(["+1-201-555-0123", nil])
    assert_equal("tel:+1-201-555-0123", uri.to_s)

    uri = @u.build(["7042", [["phone-context", "example.com"]]])
    assert_equal("tel:7042;phone-context=example.com", uri.to_s)

    uri = @u.build(["+1234", "isub=ab"])
    assert_equal("tel:+1234;isub=ab", uri.to_s)
  end

  def test_build_hash
    uri = @u.build(number: "7042",
                   params: [["phone-context", "example.com"]])
    assert_equal("tel:7042;phone-context=example.com", uri.to_s)
  end

  def test_build_validates
    assert_raise(URI::InvalidComponentError) do
      @u.build(["7042", nil])
    end
    assert_raise(URI::InvalidComponentError) do
      @u.build(number: nil)
    end
  end

  def test_query_and_fragment_rejected
    assert_raise(URI::InvalidComponentError) do
      URI("tel:+1234?x=1")
    end
    assert_raise(URI::InvalidComponentError) do
      URI("tel:+1234#frag")
    end
  end

  def test_components
    uri = URI("tel:+1234;ext=9")
    assert_equal([:scheme, :number, :params], uri.component)
    assert_equal(["tel", "+1234", [["ext", "9"]]], uri_to_ary(uri))
  end
end
