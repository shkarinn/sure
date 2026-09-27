require "test_helper"

class Account::LogoFetcherTest < ActiveSupport::TestCase
  GOOGLE_URL = "https://www.google.com/s2/favicons?domain=tbank.ru&sz=256"
  DUCKDUCKGO_URL = "https://icons.duckduckgo.com/ip3/tbank.ru.ico"
  YANDEX_URL = "https://favicon.yandex.net/favicon/v2/tbank.ru?size=120"

  setup do
    @account = accounts(:depository)
    @account.update!(institution_domain: "tbank.ru")
    stub_request(:get, YANDEX_URL).to_return(status: 404)
  end

  test "attaches the largest icon the favicon services return" do
    stub_request(:get, GOOGLE_URL).to_return(status: 200, body: png(64))
    stub_request(:get, DUCKDUCKGO_URL).to_return(status: 200, body: ico(128))

    assert Account::LogoFetcher.new(@account).fetch

    assert @account.reload.logo.attached?
    assert_equal ico(128).bytesize, @account.logo.blob.byte_size
    assert_equal "tbank.ru.ico", @account.logo.filename.to_s
  end

  test "uses Yandex when it has the only real icon" do
    stub_request(:get, GOOGLE_URL).to_return(status: 200, body: png(16))
    stub_request(:get, DUCKDUCKGO_URL).to_return(status: 404)
    stub_request(:get, YANDEX_URL).to_return(status: 200, body: png(120))

    assert Account::LogoFetcher.new(@account).fetch

    assert_equal png(120).bytesize, @account.reload.logo.blob.byte_size
  end

  test "follows the favicon service redirect" do
    stub_request(:get, GOOGLE_URL)
      .to_return(status: 301, headers: { "Location" => "https://t3.gstatic.com/faviconV2?url=http://tbank.ru&size=128" })
    stub_request(:get, "https://t3.gstatic.com/faviconV2?url=http://tbank.ru&size=128").to_return(status: 200, body: png(128))
    stub_request(:get, DUCKDUCKGO_URL).to_return(status: 404)

    assert Account::LogoFetcher.new(@account).fetch

    assert_equal png(128).bytesize, @account.reload.logo.blob.byte_size
    assert_equal "image/png", @account.logo.content_type
  end

  test "reads the size of JPEG icons" do
    stub_request(:get, GOOGLE_URL).to_return(status: 200, body: jpeg(128))
    stub_request(:get, DUCKDUCKGO_URL).to_return(status: 200, body: png(32))

    assert Account::LogoFetcher.new(@account).fetch

    assert_equal "image/jpeg", @account.reload.logo.content_type
    assert_equal "tbank.ru.jpg", @account.logo.filename.to_s
  end

  test "ignores tiny default icons" do
    stub_request(:get, GOOGLE_URL).to_return(status: 200, body: png(16))
    stub_request(:get, DUCKDUCKGO_URL).to_return(status: 200, body: ico(16))

    assert_not Account::LogoFetcher.new(@account).fetch
    assert_not @account.reload.logo.attached?
  end

  test "treats failed or unreadable responses as missing" do
    stub_request(:get, GOOGLE_URL).to_timeout
    stub_request(:get, DUCKDUCKGO_URL).to_return(status: 200, body: "<html>blocked</html>")

    assert_not Account::LogoFetcher.new(@account).fetch
    assert_not @account.reload.logo.attached?
  end

  test "does nothing without a usable institution domain" do
    @account.update!(institution_domain: nil)
    assert_not Account::LogoFetcher.new(@account).fetch

    @account.update!(institution_domain: "bad domain.ru")
    assert_not Account::LogoFetcher.new(@account).fetch

    assert_not_requested :get, /google|duckduckgo|yandex/
  end

  private
    def png(size)
      "\x89PNG\r\n\x1a\n".b + [ 13 ].pack("N") + "IHDR" + [ size, size ].pack("NN") + "\x08\x06\x00\x00\x00".b + "\x00" * 4
    end

    def jpeg(size)
      app0 = "\xFF\xE0".b + [ 16 ].pack("n") + "JFIF\x00".b + "\x00" * 9
      sof0 = "\xFF\xC0".b + [ 17, 8, size, size, 3 ].pack("nCnnC") + "\x00" * 9
      "\xFF\xD8".b + app0 + sof0 + "\xFF\xD9".b
    end

    def ico(size)
      image = png(size)
      dimension = size >= 256 ? 0 : size
      "\x00\x00\x01\x00".b + [ 1 ].pack("v") + [ dimension, dimension, 0, 0 ].pack("C4") + [ 1, 32, image.bytesize, 22 ].pack("vvVV") + image
    end
end
