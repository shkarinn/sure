# Institution app icons (512px) from the iTunes Search API, which needs no key.
# Only apps whose developer website is the institution's domain count, so a
# similarly named app from someone else never becomes the logo.
class Account::LogoFetcher::AppStore
  SEARCH_URL = "https://itunes.apple.com/search"
  LOOKUP_URL = "https://itunes.apple.com/lookup"
  ARTWORK_HOST = /\A[a-z0-9-]+\.mzstatic\.com\z/
  MAX_APPS = 3

  def initialize(domain:, term:, countries:, client:)
    @domain = domain
    @term = term
    @countries = countries
    @client = client
  end

  def icons
    apps = @countries.flat_map { |country| results(SEARCH_URL, term: @term, country: country, entity: "software", limit: 10) }
    apps.uniq { |app| app["trackId"] }.select { |app| own_app?(app) }.first(MAX_APPS).filter_map { |app| icon_from(app) }
  end

  def icon(track_id)
    return unless track_id.to_s.match?(/\A\d+\z/)

    app = @countries.lazy.flat_map { |country| results(LOOKUP_URL, id: track_id, country: country) }.first
    icon_from(app) if app && own_app?(app)
  end

  private
    def results(url, params)
      Array(@client.json("#{url}?#{params.to_query}")&.dig("results"))
    end

    def own_app?(app)
      Account::LogoFetcher.same_site?(app["sellerUrl"], @domain)
    end

    def icon_from(app)
      url = app["artworkUrl512"].to_s
      return unless URI.parse(url).then { |uri| uri.scheme == "https" && uri.host.to_s.match?(ARTWORK_HOST) }

      @client.icon(url, key: "appstore:#{app["trackId"]}", source: "appstore", name: app["trackName"])
    rescue URI::InvalidURIError
      nil
    end
end
