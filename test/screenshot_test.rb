require "test_helper"
require "support/no_network"
require "stringio"
require "timeout"
require "handrail/bug_reporter/screenshot"
require "handrail/bug_reporter/payload"

class ScreenshotTest < ScaffoldTestCase
  Screenshot = Handrail::BugReporter::Screenshot
  Payload = Handrail::BugReporter::Payload
  PNG = File.binread(File.join(ROOT, "test/fixtures/screenshots/pixel.png")).freeze
  JPEG = File.binread(File.join(ROOT, "test/fixtures/screenshots/pixel.jpg")).freeze
  WIRE_FIELDS = %w[screenshot_base64 screenshot_filename screenshot_mime_type].freeze

  class ReadSpy
    attr_reader :requests, :returned

    def initialize(data, short_read = nil, endless = false)
      @data, @short_read, @endless = data, short_read, endless
      @requests, @returned, @offset = [], 0, 0
    end

    def read(length)
      @requests << length
      raise "unbounded read" unless length.is_a?(Integer) && length > 0 && length <= Screenshot::READ_BYTES
      size = @short_read ? [length, @short_read].min : length
      chunk = @endless ? "x" * size : @data.byteslice(@offset, size)
      @offset += chunk.bytesize if chunk
      @returned += chunk.bytesize if chunk
      chunk
    end

    def size; raise "size must not be trusted"; end
    def rewind; raise "must not rewind"; end
    def close; raise "must not close caller IO"; end
    def eof?; raise "must not rely on eof?"; end
    def path; raise "must not use paths"; end
  end

  def normalize(data, options = {})
    Screenshot.normalize({ :data => data }.merge(options), :allow_screenshots => true)
  end

  def payload(input = {}, options = {})
    Payload.new({ :title => "Title", :description => "Description" }.merge(input),
      **{ :project_id => "trusted-project", :environment => "dev" }.merge(options))
  end

  def assert_invalid(error_class = Screenshot::Error)
    error = assert_raises(error_class) { yield }
    assert_equal "invalid_screenshot", error.code
    assert_equal Screenshot::ERROR_MESSAGE, error.message
    assert_nil error.cause
    error
  end

  def test_png_and_jpeg_in_all_explicit_formats
    [[PNG, "image/png", "screenshot.png"], [JPEG, "image/jpeg", "screenshot.jpg"]].each do |bytes, mime, filename|
      encoded = Base64.strict_encode64(bytes)
      inputs = [
        { :data => bytes }, { :data => StringIO.new(bytes) },
        { :data => ReadSpy.new(bytes, 2), :encoding => :binary },
        { :data => encoded, :encoding => :base64 },
        { :data => "data:#{mime};base64,#{encoded}", :encoding => :data_url }
      ]
      inputs.each do |attachment|
        result = Screenshot.normalize(attachment.merge(:mime_type => mime), :allow_screenshots => true)
        assert_equal WIRE_FIELDS.sort, result.keys.sort
        assert_equal encoded, result["screenshot_base64"]
        assert_equal bytes, Base64.strict_decode64(result["screenshot_base64"])
        assert_equal mime, result["screenshot_mime_type"]
        assert_equal filename, result["screenshot_filename"]
        assert result.frozen?
        assert result.values.all?(&:frozen?)
      end
    end
    assert_equal "image/jpeg", normalize("DATA:IMAGE/JPEG;BASE64,#{Base64.strict_encode64(JPEG)}",
      :encoding => "data_url", :mime_type => " IMAGE/JPEG ")["screenshot_mime_type"]
  end

  def test_string_keys_and_explicit_encoding_are_required_for_encoded_strings
    result = Screenshot.normalize({ "data" => PNG, "mimeType" => "image/png", "encoding" => "binary" },
      :allow_screenshots => true)
    assert_equal "image/png", result["screenshot_mime_type"]
    assert_invalid { normalize(Base64.strict_encode64(PNG)) }
    assert_invalid { normalize("data:image/png;base64,#{Base64.strict_encode64(PNG)}") }
    assert_invalid { Screenshot.normalize(PNG, :allow_screenshots => true) }
    assert_invalid { normalize(PNG, :encoding => "guess") }
    assert_invalid { normalize(PNG, :encoding => false) }
    assert_invalid { normalize(StringIO.new(PNG), :encoding => "base64") }
  end

  def test_caller_opened_binary_file_is_consumed_without_rewind_or_close
    File.open(File.join(ROOT, "test/fixtures/screenshots/pixel.jpg"), "rb") do |io|
      assert_equal Base64.strict_encode64(JPEG), normalize(io)["screenshot_base64"]
      refute io.closed?
      assert_equal JPEG.bytesize, io.pos
    end
    io = StringIO.new("skip" + PNG)
    io.pos = 4
    assert_equal Base64.strict_encode64(PNG), normalize(io)["screenshot_base64"]
    refute io.closed?
  end

  def test_declared_mime_must_be_supported_and_match_every_source
    ["image/jpeg", "image/gif", "image/jpg", "text/plain", "image/png; charset=binary", false, 3, [], {}].each do |mime|
      assert_invalid { normalize(PNG, :mime_type => mime) }
    end
    assert_invalid { normalize(JPEG, :mime_type => "image/png") }
    assert_invalid { normalize(Base64.strict_encode64(PNG), :encoding => :base64, :mime_type => "image/jpeg") }
    assert_invalid { normalize("data:image/jpeg;base64,#{Base64.strict_encode64(PNG)}", :encoding => :data_url) }
    assert_invalid do
      normalize("data:image/png;base64,#{Base64.strict_encode64(PNG)}", :encoding => :data_url, :mime_type => "image/jpeg")
    end
    assert_equal "image/png", normalize(PNG, :mime_type => "")["screenshot_mime_type"]
  end

  def test_empty_invalid_and_unsupported_inputs
    [nil, false, 1, [], {}, Object.new, "", "secret-attachment", "GIF89a", "RIFFxxxxWEBP",
      PNG.byteslice(0, 7), JPEG.byteslice(0, 2)].each do |data|
      assert_invalid { normalize(data) }
    end
    [nil, false, [], 42, {}, "filename.png"].each do |attachment|
      assert_invalid { Screenshot.normalize(attachment, :allow_screenshots => true) }
    end
    assert_invalid { normalize(Base64.strict_encode64("not an image"), :encoding => :base64) }
  end

  def test_strict_base64_and_data_url_rejection
    ["", "a", "a===", "====", "AA=A", "AA?=", "AB==", "AAA", "AA==\n", " AA==", "AA-_", "\xff".b].each do |encoded|
      assert_invalid { normalize(encoded, :encoding => :base64) }
    end
    encoded = Base64.strict_encode64(PNG)
    ["data:;base64,#{encoded}", "data:image/png,#{encoded}", "data:image/png;charset=utf-8;base64,#{encoded}",
      "data:image/gif;base64,#{encoded}", "data:image/png;base64,", "data:image/png;base64,#{encoded}%20",
      " data:image/png;base64,#{encoded}", "https://fixture.invalid/image.png"].each do |url|
      assert_invalid { normalize(url, :encoding => :data_url) }
    end
  end

  def test_disabled_gate_precedes_io_decoding_and_hooks
    io = ReadSpy.new(PNG)
    decoded = false
    decoder = lambda { |_| decoded = true; raise "decoder must not be reached" }
    Base64.stub(:strict_decode64, decoder) do
      [false, nil, 0, 1, "true", :true].each do |enabled|
        assert_invalid { Screenshot.normalize({ :data => io }, :allow_screenshots => enabled) }
        assert_invalid { Screenshot.normalize({ :data => "AAAA", :encoding => :base64 }, :allow_screenshots => enabled) }
      end
      assert_invalid { Screenshot.normalize({ :data => io }) }
      hook_called = false
      assert_invalid(Payload::Error) do
        payload({ :screenshot => { :data => io }, :allow_screenshots => true, :allowScreenshots => true },
          :redaction_hooks => [lambda { |fields| hook_called = true; fields }])
      end
      refute hook_called
    end
    refute decoded
    assert_empty io.requests
  end

  def test_safe_filenames_and_mime_matching_fallbacks
    assert_equal ".._folder_name____.png", normalize(PNG, :filename => " ../folder\\name\r\n\x00\x7f.png ")["screenshot_filename"]
    assert_equal "x_y.png", normalize(PNG, :filename => "x\u0085y.png")["screenshot_filename"]
    assert_equal "猫" * 200, normalize(PNG, :filename => "猫" * 201)["screenshot_filename"]
    assert_equal 200, normalize(PNG, :filename => "x" * 205)["screenshot_filename"].length
    [nil, false, 2, "", " \t\n", "\u00a0\ufeff", "\xff".b, "\xff".dup.force_encoding("UTF-8")].each do |name|
      assert_equal "screenshot.png", normalize(PNG, :filename => name)["screenshot_filename"]
      assert_equal "screenshot.jpg", normalize(JPEG, :filename => name)["screenshot_filename"]
    end
  end

  def test_exact_size_boundary_and_one_byte_over_for_every_format
    bytes = PNG + "x" * (Screenshot::MAX_SCREENSHOT_BYTES - PNG.bytesize)
    [0, 1].each do |extra|
      data = extra == 0 ? bytes : bytes + "x"
      encoded = Base64.strict_encode64(data)
      io = ReadSpy.new(data)
      inputs = [{ :data => data }, { :data => io }, { :data => encoded, :encoding => :base64 },
        { :data => "data:image/png;base64,#{encoded}", :encoding => :data_url }]
      inputs.each do |attachment|
        if extra == 0
          result = Screenshot.normalize(attachment, :allow_screenshots => true)
          assert_equal encoded, result["screenshot_base64"]
        else
          assert_invalid { Screenshot.normalize(attachment, :allow_screenshots => true) }
        end
      end
      assert_equal Screenshot::MAX_SCREENSHOT_BYTES + extra, io.returned
      assert_equal 1, io.requests.last
      assert_equal 321, io.requests.length
    end
  end

  def test_oversized_encoded_input_is_rejected_before_decoding_or_slicing
    called = false
    decoder = lambda { |_| called = true; raise "must not decode oversized input" }
    one_over = Base64.strict_encode64(PNG + "x" * (Screenshot::MAX_SCREENSHOT_BYTES + 1 - PNG.bytesize))
    huge = " " * (Screenshot::MAX_BASE64_BYTES + 24)
    sliced = false
    huge.define_singleton_method(:byteslice) { |*args| sliced = true; raise "must not slice oversized input" }
    Base64.stub(:strict_decode64, decoder) do
      [one_over, huge].each do |data|
        assert_invalid { normalize(data, :encoding => :base64) }
        assert_invalid { normalize("data:image/png;base64,#{data}", :encoding => :data_url) }
      end
      assert_invalid { normalize(huge, :encoding => :data_url) }
    end
    refute called
    refute sliced
  end

  def test_short_reads_and_endless_io_have_bounded_requests
    short = ReadSpy.new(PNG, 1)
    assert_equal Base64.strict_encode64(PNG), normalize(short)["screenshot_base64"]
    assert_equal PNG.bytesize + 1, short.requests.length
    endless = ReadSpy.new(nil, nil, true)
    Timeout.timeout(5) { assert_invalid { normalize(endless) } }
    assert_equal Screenshot::MAX_SCREENSHOT_BYTES + 1, endless.returned
    assert_equal 321, endless.requests.length
    assert_equal 1, endless.requests.last
    empty = Object.new
    calls = 0
    empty.define_singleton_method(:read) { |_| calls += 1; "" }
    assert_invalid { normalize(empty) }
    assert_equal 1, calls
  end

  def test_invalid_io_responses_and_private_exceptions
    [false, 42, "x" * (Screenshot::READ_BYTES + 1)].each do |response|
      io = Object.new
      calls = 0
      io.define_singleton_method(:read) { |_| calls += 1; response }
      assert_invalid { normalize(io) }
      assert_equal 1, calls
    end
    io = Object.new
    def io.read(_length); raise IOError, "private-attachment-contents"; end
    [Screenshot::Error, Payload::Error].each do |klass|
      error = assert_invalid(klass) do
        if klass == Screenshot::Error
          normalize(io)
        else
          payload({ :screenshot => { :data => io } }, :allow_screenshots => true)
        end
      end
      refute_match(/private-attachment-contents/, error.inspect + error.message + error.backtrace.join)
    end
  end

  def test_payload_preserves_validated_attachment_and_trusted_fields_against_injection
    io = ReadSpy.new(PNG, 7)
    filename = "original.png"
    attachment = { :data => io, :filename => filename }
    injected = { "screenshot" => { :data => JPEG }, "allow_screenshots" => true,
      "screenshot_base64" => "forged", "screenshot_filename" => "forged.jpg", "screenshot_mime_type" => "image/jpeg",
      "project_id" => "foreign", "source" => "foreign" }
    hooks = [lambda do |fields|
      assert_empty fields.keys & (WIRE_FIELDS + %w[screenshot allow_screenshots])
      assert_equal Payload::REDACTED, fields["metadata"]["password"]
      fields.merge(injected)
    end, lambda do |fields|
      assert_empty fields.keys & injected.keys
      fields
    end]
    report = payload(injected.merge(:metadata => { :password => "private" }, "screenshot" => attachment),
      :allow_screenshots => true, :redaction_hooks => hooks)
    calls = io.requests.length
    attachment[:data] = JPEG
    filename.replace("mutated.jpg")
    2.times do
      body = JSON.parse(report.to_json)
      assert_equal Base64.strict_encode64(PNG), body["screenshot_base64"]
      assert_equal "original.png", body["screenshot_filename"]
      assert_equal "image/png", body["screenshot_mime_type"]
      assert_equal "trusted-project", body["project_id"]
      assert_equal Handrail::BugReporter::Identity::SDK_IDENTITY["source"], body["source"]
    end
    assert_equal calls, io.requests.length
    WIRE_FIELDS.each { |field| assert report.to_h[field].frozen? }
    [false, true].each do |enabled|
      body = payload(injected.reject { |key, _| key == "screenshot" },
        :allow_screenshots => enabled, :redaction_hooks => [lambda { |fields| fields.merge(injected) }]).to_h
      assert_empty body.keys & WIRE_FIELDS
    end
    assert_invalid(Payload::Error) { payload(:screenshot => "injected") }
    assert_invalid(Payload::Error) { payload({ :screenshot => "injected" }, :allow_screenshots => true) }
    assert_empty payload(:screenshot => nil).to_h.keys & WIRE_FIELDS
  end

  def test_validation_never_opens_files_or_fetches_urls
    attempts = []
    reject = lambda { |*args| attempts << "open/read"; raise "implicit access forbidden" }
    File.stub(:open, reject) do
      File.stub(:read, reject) do
        File.stub(:binread, reject) do
          IO.stub(:read, reject) do
            IO.stub(:binread, reject) do
              IO.stub(:popen, reject) do
                Kernel.stub(:open, reject) do
                  ["/etc/passwd", File.join(ROOT, "test/fixtures/screenshots/pixel.png"),
                    "https://fixture.invalid/image.png", "file:///etc/passwd", "|cat /etc/passwd"].each do |input|
                    assert_invalid { normalize(input) }
                    assert_invalid { normalize(input, :encoding => :data_url) }
                    assert_invalid(Payload::Error) { payload({ :screenshot => { :data => input } }, :allow_screenshots => true) }
                  end
                  assert_equal "image/png", normalize(PNG)["screenshot_mime_type"]
                end
              end
            end
          end
        end
      end
    end
    assert_empty attempts
    assert_empty NoNetwork::ATTEMPTS
  end
end
