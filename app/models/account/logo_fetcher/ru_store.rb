# Institution app icons (512px) from RuStore, the Russian Android store that
# lists banks missing from Google Play and the App Store. Its catalogue search
# needs no key, but apps carry the publisher's legal name rather than a
# website, so an app only counts when its package name holds the domain's
# brand: "com.yandex.bank" for bank.yandex.ru, "kz.bankffin.app" for bankffin.kz.
class Account::LogoFetcher::RuStore
  SEARCH_URL = "https://backapi.rustore.ru/applicationData/apps"
  ICON_HOST = "static.rustore.ru"
  # Domain labels that name no one in particular.
  GENERIC_LABELS = %w[www com net org bank online finance app mobile my].freeze
  MAX_APPS = 3

  def initialize(domain:, term:, client:)
    @domain = domain
    @term = term
    @client = client
  end

  def icons
    own_apps.first(MAX_APPS).filter_map { |app| icon_from(app) }
  end

  # RuStore has no public lookup by package, so the picked app is found again
  # through the same search that listed it.
  def icon(package)
    app = own_apps.find { |candidate| candidate["packageName"] == package }
    icon_from(app) if app
  end

  private
    def own_apps
      apps = Array(@client.json("#{SEARCH_URL}?#{{ query: @term, pageSize: 10 }.to_query}")&.dig("body", "content"))
      apps.select { |app| own_app?(app["packageName"]) }
    end

    def own_app?(package)
      segments = package.to_s.downcase.split(".")
      brands.any? { |brand| segments.any? { |segment| segment.start_with?(brand) } }
    end

    def brands
      @domain.split(".")[0...-1].select { |label| label.length >= 3 } - GENERIC_LABELS
    end

    def icon_from(app)
      url = app["iconUrl"].to_s
      return unless URI.parse(url).then { |uri| uri.scheme == "https" && uri.host == ICON_HOST }

      @client.icon(url, key: "rustore:#{app["packageName"]}", source: "rustore", name: app["appName"])
    rescue URI::InvalidURIError
      nil
    end
end
