# Ruby screenshot attachment contract

`Payload.new` accepts `input[:screenshot]` (or `input["screenshot"]`) and a
separate trusted `allow_screenshots: true` keyword. The keyword defaults to false
and requires literal `true`. Derive it from trusted server configuration/policy,
never browser input or redaction hooks. No configuration or client behavior is
changed by this implementation.

```ruby
require "handrail/bug_reporter/payload"

payload = Handrail::BugReporter::Payload.new(
  { :title => "Checkout fails", :description => "Click Pay",
    :screenshot => { :data => png_bytes, :filename => "checkout.png",
      :mime_type => "image/png" } },
  :project_id => configuration.project_id,
  :environment => configuration.environment,
  :allow_screenshots => true
)
```

An attachment must be a hash with string or symbol keys. String keys win over
symbol keys. `data` is required; `filename` and `mime_type` are optional.
`mimeType` is accepted as an alias, with `mime_type` taking precedence.

| `encoding` | `data` |
| --- | --- |
| Omitted, nil, `"binary"` or `:binary` | Binary String or caller-provided IO implementing bounded `read(length)` |
| `"base64"` or `:base64` | Strict, padded RFC 4648 base64 String |
| `"data_url"` or `:data_url` | `data:image/png;base64,...` or `data:image/jpeg;base64,...` String; prefix is case-insensitive |

Unlike JS's whitespace/unpadded base64 normalization, Ruby deliberately requires
canonical padded base64 without whitespace. Data URLs cannot include additional
parameters or percent escapes. Encoded formats must be explicitly selected;
binary strings are never guessed to be base64, paths, commands or URLs. The
validator never opens files or fetches resources. Caller-provided IO adapters
are responsible for their own `read` implementation and blocking behavior.
The validator reads from the current position, never seeks, rewinds or closes
the caller's IO, and does not call `size`, `eof?`, `path` or custom serializers.

An absent/nil screenshot preserves existing payload behavior. Other attachment
values, including false, must pass validation. Disabled attachments fail before
IO reads, decoding or redaction hooks. Standalone callers can use
`Screenshot.normalize(attachment, :allow_screenshots => true)` after requiring
`handrail/bug_reporter/screenshot`.

Validation detects PNG's eight-byte or JPEG's three-byte signature, rejects
empty/unsupported content, and checks any declared MIME and data URL MIME
against that signature. Declared MIME is trimmed and case-insensitive; supported
values are `image/png` and `image/jpeg` (blank means unspecified). This matches
JS's signature check, not a full image decoder or structural integrity check.

The decoded size limit is exactly 20,971,520 bytes (20 MiB), inclusive. Binary
strings are size-checked before copying. IO requests are at most 65,536 bytes;
the remaining allowance plus one byte bounds every request. Short reads continue,
nil/empty reads terminate, and responses larger than requested are rejected
before appending. An endless stream returning requested lengths stops after
321 calls and 20,971,521 bytes; even one-byte short reads have a finite byte/call
budget. The SDK cannot interrupt a caller's blocking `read` implementation.

Base64 input is limited to 27,962,028 bytes before decoding. Padding is checked
in the size estimate, so a 20 MiB + 1 input is rejected even though its encoded
length equals the exact boundary's encoded length. Data URL total size is
checked before header slicing; its encoded length is checked before extracting
the body. Strict decoding rejects malformed alphabet, padding and trailing bits.

The normalized result contains only `screenshot_base64`, `screenshot_filename`
and `screenshot_mime_type`. Filenames are trimmed, separators and control
characters become underscores, and names are capped at 200 complete Ruby
characters. Missing, blank or invalidly encoded names fall back to
`screenshot.png` or `screenshot.jpg` according to detected MIME. Caller-supplied
extensions are otherwise retained, as in JS.

Payload captures/validates the attachment before hooks and merges the validated
wire fields before deep freezing. Hooks never receive the attachment or its
wire fields; caller/hook wire-field injections cannot create or replace an
attachment or enable screenshots. Serialization/retries reuse the frozen result
without reading IO again. Existing identity, redaction and report-field allowlist
behavior is retained.

All failures expose `invalid_screenshot` with the fixed JS-compatible message
“The screenshot must be one PNG or JPEG image no larger than 20 MiB.” Standalone
normalization raises `Screenshot::Error`; payload construction translates it to
`Payload::Error`. Neither exposes the original exception message or cause.

## Focused verification

The tests use `test/support/no_network.rb`, binary fixtures, bounded IO spies,
decoder spies and file-opening spies. There is no database or live service
dependency. See `test/screenshot_test.rb` and the existing payload regression
suite. Ruby >= 2.3 syntax is retained; legacy runtime/framework support remains
unverified until the separate compatibility task runs.

Worker validation on 2026-09-09 used Ruby 3.1.2p20 (x86_64-linux-gnu),
Minitest 5.15.0 and Ruby's standard-library Base64. The `bundle` executable was
unavailable; these focused tests run directly without Rails or Bundler.

```sh
ruby -Ilib:test -rsupport/no_network -e 'require_relative "test/screenshot_test"; require_relative "test/payload_test"'
```

Result: 73 runs, 855 assertions, zero failures/errors/skips, zero network
attempts. Baseline `ruby -Ilib:test test/payload_test.rb` passed 59 runs and
278 assertions before edits. `ruby -c` passed for screenshot.rb, payload.rb,
screenshot_test.rb and payload_test.rb on the available Ruby. Scoped whitespace
checks (including untracked files) and `git diff --check` passed. The existing
gemspec includes screenshot.rb and still declares Ruby >= 2.3.

Only this item's focused tests were run while sibling writers were active;
no unrelated test failure was encountered. Ruby 2.3 and Rails framework boot
were not executed. This source implementation and test evidence are ready for
dispatcher reassessment and are not linked QA campaign acceptance. No client,
route, browser asset, integration, configuration or release changes were made
by this item.
