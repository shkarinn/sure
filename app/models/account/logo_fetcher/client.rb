# HTTP for Account::LogoFetcher: follows https redirects, treats network
# failures as "nothing found", and turns image responses into sized icons.
class Account::LogoFetcher::Client
  # Favicon services answer unknown domains with a 16px (or 1px) placeholder.
  MIN_SIZE = 17
  MAX_REDIRECTS = 3

  def get(url, redirects_left = MAX_REDIRECTS)
    response = connection.get(url)
    location = response.headers["location"].to_s

    if response.status.in?(300..399)
      get(location, redirects_left - 1) if redirects_left.positive? && location.start_with?("https://")
    elsif response.status == 200
      response
    end
  rescue Faraday::Error => e
    Rails.logger.info("Account logo request failed: url=#{url} error=#{e.message}")
    nil
  end

  def json(url)
    body = get(url)&.body
    JSON.parse(body) if body
  rescue JSON::ParserError
    nil
  end

  def icon(url, key:, source:, name: nil)
    body = get(url)&.body&.b
    return if body.nil? || body.bytesize > Account::LOGO_MAX_SIZE

    size, content_type, extension = image_format(body)
    Account::LogoFetcher::Icon.new(key:, source:, name:, body:, size:, content_type:, extension:) if size.to_i >= MIN_SIZE
  end

  # Runs the lambdas in threads (the work is waiting on HTTP) and returns their results in order.
  def in_parallel(tasks)
    threads = tasks.map { |task| Thread.new { Rails.application.executor.wrap { task.call } } }
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
  end

  private
    def connection
      @connection ||= Faraday.new(request: { open_timeout: 5, timeout: 10 })
    end

    # Reads the pixel width from the file header; formats we cannot size are skipped.
    def image_format(body)
      if body.start_with?("\x89PNG\r\n\x1a\n".b) && body.bytesize >= 24
        [ body.byteslice(16, 4).unpack1("N"), "image/png", "png" ]
      elsif body.start_with?("\x00\x00\x01\x00".b) && body.bytesize >= 6
        count = body.byteslice(4, 2).unpack1("v")
        widths = (0...count).filter_map { |i| body.getbyte(6 + i * 16) }
        # A width byte of 0 means 256px.
        [ widths.map { |width| width.zero? ? 256 : width }.max, "image/vnd.microsoft.icon", "ico" ]
      elsif body.start_with?("GIF8") && body.bytesize >= 8
        [ body.byteslice(6, 2).unpack1("v"), "image/gif", "gif" ]
      elsif body.start_with?("\xFF\xD8".b)
        [ jpeg_width(body), "image/jpeg", "jpg" ]
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
