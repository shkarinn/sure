# Downloads an institution's icon through public favicon services and stores
# it as the account's own logo. Brandfetch refuses server-side downloads and
# bank sites block bots, while these services' crawlers already collected the
# sites' touch and manifest icons.
class Account::LogoFetcher
  SOURCES = [
    ->(domain) { "https://www.google.com/s2/favicons?domain=#{domain}&sz=256" },
    ->(domain) { "https://icons.duckduckgo.com/ip3/#{domain}.ico" },
    ->(domain) { "https://favicon.yandex.net/favicon/v2/#{domain}?size=120" }
  ].freeze

  # The services answer unknown domains with a 16px (or 1px) placeholder.
  MIN_SIZE = 17
  MAX_REDIRECTS = 3
  DOMAIN_FORMAT = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/

  Icon = Data.define(:body, :size, :content_type, :extension)

  attr_reader :account

  def initialize(account)
    @account = account
  end

  # Returns true when an icon was attached.
  def fetch
    domain = account.institution_domain
    return false unless domain.to_s.match?(DOMAIN_FORMAT)

    icon = SOURCES.filter_map { |source| download(source.call(domain)) }.max_by(&:size)
    return false unless icon

    account.logo.attach(
      io: StringIO.new(icon.body),
      filename: "#{domain}.#{icon.extension}",
      content_type: icon.content_type
    )
  end

  private
    def download(url, redirects_left = MAX_REDIRECTS)
      response = client.get(url)
      location = response.headers["location"].to_s

      if response.status.in?(300..399)
        download(location, redirects_left - 1) if redirects_left.positive? && location.start_with?("https://")
      elsif response.status == 200 && response.body.bytesize <= Account::LOGO_MAX_SIZE
        icon = parse(response.body.b)
        icon if icon && icon.size >= MIN_SIZE
      end
    rescue Faraday::Error => e
      Rails.logger.info("Account logo download failed: url=#{url} error=#{e.message}")
      nil
    end

    def client
      @client ||= Faraday.new(request: { open_timeout: 5, timeout: 10 })
    end

    # Reads the pixel width from the file header; formats we cannot size are skipped.
    def parse(body)
      if body.start_with?("\x89PNG\r\n\x1a\n".b) && body.bytesize >= 24
        Icon.new(body, body.byteslice(16, 4).unpack1("N"), "image/png", "png")
      elsif body.start_with?("\x00\x00\x01\x00".b) && body.bytesize >= 6
        count = body.byteslice(4, 2).unpack1("v")
        widths = (0...count).filter_map { |i| body.getbyte(6 + i * 16) }
        # A width byte of 0 means 256px.
        Icon.new(body, widths.map { |width| width.zero? ? 256 : width }.max.to_i, "image/vnd.microsoft.icon", "ico")
      elsif body.start_with?("GIF8") && body.bytesize >= 8
        Icon.new(body, body.byteslice(6, 2).unpack1("v"), "image/gif", "gif")
      elsif body.start_with?("\xFF\xD8".b) && (width = jpeg_width(body))
        Icon.new(body, width, "image/jpeg", "jpg")
      end
    end

    # Walks the JPEG segments to the start-of-frame one, which holds the dimensions.
    def jpeg_width(body)
      position = 2
      while position + 9 <= body.bytesize && body.getbyte(position) == 0xFF
        marker = body.getbyte(position + 1)
        return body.byteslice(position + 7, 2).unpack1("n") if marker.between?(0xC0, 0xCF) && ![ 0xC4, 0xC8, 0xCC ].include?(marker)

        position += 2 + body.byteslice(position + 2, 2).unpack1("n")
      end
    end
end
