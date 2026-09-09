require "base64"

module Handrail
  module BugReporter
    # Explicit attachment hash: data (String or binary IO), encoding (binary,
    # base64 or data_url), optional filename and mime_type. No path/URL loading.
    class Screenshot
      MAX_SCREENSHOT_BYTES = 20 * 1024 * 1024
      MAX_BASE64_BYTES = ((MAX_SCREENSHOT_BYTES + 2) / 3) * 4
      READ_BYTES = 64 * 1024
      ERROR_MESSAGE = "The screenshot must be one PNG or JPEG image no larger than 20 MiB.".freeze
      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
      JPEG_SIGNATURE = "\xff\xd8\xff".b.freeze

      class Error < StandardError
        def initialize
          super(ERROR_MESSAGE)
        end

        def code
          "invalid_screenshot"
        end
      end

      class << self
        def normalize(attachment, allow_screenshots: false)
          begin
            raise Error unless allow_screenshots.equal?(true)
            return normalize_attachment(attachment)
          rescue StandardError
            # Do not retain an IO/decoder exception, its message or implicit cause.
          end
          raise Error.new, cause: nil
        end

        private

        def read(hash, key, alternate = nil)
          [key, alternate].compact.each do |name|
            return hash[name] if hash.key?(name)
            return hash[name.to_sym] if hash.key?(name.to_sym)
          end
          nil
        end

        def normalize_attachment(attachment)
          raise Error unless attachment.is_a?(Hash)
          data = read(attachment, "data")
          declared = normalize_mime(read(attachment, "mime_type", "mimeType"))
          encoding = read(attachment, "encoding")
          encoding = "binary" if encoding.nil?
          case encoding
          when "binary", :binary
            bytes = data.is_a?(String) ? binary_string(data) : read_io(data)
          when "base64", :base64
            bytes = decode_base64(data)
          when "data_url", :data_url
            # Check total input size before slicing even the bounded header.
            raise Error unless data.is_a?(String) && data.bytesize <= MAX_BASE64_BYTES + 23
            header = /\Adata:(image\/png|image\/jpeg);base64,/i.match(data.byteslice(0, 23).b)
            raise Error unless header
            url_mime = header[1].downcase
            raise Error if declared && declared != url_mime
            declared = url_mime
            encoded_length = data.bytesize - header[0].bytesize
            raise Error if encoded_length > MAX_BASE64_BYTES
            bytes = decode_base64(data.byteslice(header[0].bytesize, encoded_length))
          else
            raise Error
          end
          detected = if bytes.start_with?(PNG_SIGNATURE)
            "image/png"
          elsif bytes.start_with?(JPEG_SIGNATURE)
            "image/jpeg"
          end
          raise Error unless detected && (!declared || declared == detected)
          {
            "screenshot_base64" => Base64.strict_encode64(bytes).freeze,
            "screenshot_filename" => safe_filename(read(attachment, "filename"), detected).freeze,
            "screenshot_mime_type" => detected.freeze
          }.freeze
        end

        def normalize_mime(value)
          return nil if value.nil?
          raise Error unless value.is_a?(String) && value.bytesize <= 128
          mime = value.strip.downcase
          return nil if mime.empty?
          raise Error unless ["image/png", "image/jpeg"].include?(mime)
          mime
        end

        def binary_string(data)
          raise Error if data.empty? || data.bytesize > MAX_SCREENSHOT_BYTES
          data.b
        end

        def read_io(io)
          raise Error unless io.respond_to?(:read)
          bytes = "".b
          loop do
            # One extra byte distinguishes the exact boundary from oversized IO.
            # Every nonempty short read consumes budget; empty/nil terminates.
            length = [READ_BYTES, MAX_SCREENSHOT_BYTES + 1 - bytes.bytesize].min
            chunk = io.read(length)
            break if chunk.nil?
            raise Error unless chunk.is_a?(String) && chunk.bytesize <= length
            break if chunk.empty?
            raise Error if bytes.bytesize + chunk.bytesize > MAX_SCREENSHOT_BYTES
            bytes << chunk.b
          end
          raise Error if bytes.empty?
          bytes
        end

        def decode_base64(data)
          raise Error unless data.is_a?(String)
          length = data.bytesize
          raise Error if length == 0 || length > MAX_BASE64_BYTES || length % 4 != 0
          # Strict, padded RFC 4648 base64. Account for padding BEFORE decoding:
          # boundary and boundary+1 can have the same encoded length.
          padding = data.getbyte(length - 1) == 61 ? 1 : 0
          padding += 1 if data.getbyte(length - 2) == 61
          raise Error if length / 4 * 3 - padding > MAX_SCREENSHOT_BYTES
          binary_string(Base64.strict_decode64(data))
        end

        def safe_filename(value, mime)
          fallback = mime == "image/png" ? "screenshot.png" : "screenshot.jpg"
          return fallback unless value.is_a?(String) && value.valid_encoding?
          begin
            name = value.encode(Encoding::UTF_8)
          rescue EncodingError
            return fallback
          end
          name = name.gsub(/\A[[:space:]\ufeff]+|[[:space:]\ufeff]+\z/, "")
          name = name[0, 200].gsub(/[\\\/\p{Cc}]/, "_")
          name.empty? ? fallback : name
        end
      end
    end
  end
end
