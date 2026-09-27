# Finds an institution's icon and stores it as the account's own logo.
# Brandfetch refuses server-side downloads and bank sites block bots, so the
# icons come from services that already collected them: favicon services
# (the sites' touch and manifest icons) and the institution's mobile apps in
# the App Store and Google Play, matched by the developer's website.
class Account::LogoFetcher
  FAVICON_SOURCES = {
    "google" => ->(domain) { "https://www.google.com/s2/favicons?domain=#{domain}&sz=256" },
    "duckduckgo" => ->(domain) { "https://icons.duckduckgo.com/ip3/#{domain}.ico" },
    "yandex" => ->(domain) { "https://favicon.yandex.net/favicon/v2/#{domain}?size=120" }
  }.freeze

  DOMAIN_FORMAT = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/

  # `key` identifies the icon for fetch(source:): a favicon service name, or
  # "appstore:<track id>" / "googleplay:<package>" for an app.
  Icon = Data.define(:key, :source, :name, :body, :size, :content_type, :extension)

  attr_reader :account

  def self.same_site?(host, domain)
    host = Account.normalize_institution_domain(host)
    host.present? && (host == domain || host.end_with?(".#{domain}") || domain.end_with?(".#{host}"))
  end

  def initialize(account)
    @account = account
  end

  # Real icons from every source, largest first; ties keep the source order.
  def candidates
    return [] unless domain

    # Built here, not in the threads, so database reads stay on this thread's connection.
    stores = [ app_store, google_play ]
    icons = client.in_parallel([ -> { favicon_icons }, *stores.map { |store| -> { store.icons } } ]).flatten
    icons.each_with_index.sort_by { |icon, index| [ -icon.size, index ] }.map(&:first)
  end

  # Attaches the icon with `source` key, or the largest one when no source is
  # given. `auto` marks the icon as picked by Sure, so later automatic fetches
  # may replace it. Returns true when an icon was attached.
  def fetch(source: nil, auto: false)
    return false unless domain

    icon = source ? icon_for(source) : candidates.first
    return false unless icon

    account.logo.attach(
      io: StringIO.new(icon.body),
      filename: "#{domain}.#{icon.extension}",
      content_type: icon.content_type,
      metadata: { "logo_source" => icon.source, "logo_key" => icon.key, "logo_name" => icon.name, "logo_auto" => auto }.compact
    ) && account.update!(prefer_brandfetch_logo: false)
  end

  private
    def domain
      value = account.institution_domain
      value if value.to_s.match?(DOMAIN_FORMAT)
    end

    def icon_for(key)
      group, id = key.to_s.split(":", 2)

      case group
      when *FAVICON_SOURCES.keys then favicon_icon(group) if id.nil?
      when "appstore" then app_store.icon(id)
      when "googleplay" then google_play.icon(id)
      end
    end

    def favicon_icons
      FAVICON_SOURCES.keys.filter_map { |source| favicon_icon(source) }
    end

    def favicon_icon(source)
      client.icon(FAVICON_SOURCES.fetch(source).call(domain), key: source, source: source)
    end

    def app_store
      @app_store ||= Account::LogoFetcher::AppStore.new(domain:, term: search_term, countries:, client:)
    end

    def google_play
      @google_play ||= Account::LogoFetcher::GooglePlay.new(domain:, term: search_term, country: countries.first, client:)
    end

    def search_term
      account.institution_name.presence || domain.split(".").first
    end

    # App catalogues differ per country: the domain's own country ("bankffin.kz"),
    # the family's, then the US store, which lists most international apps.
    def countries
      tld = domain.split(".").last
      [ (tld if tld.length == 2), account.family&.country, "us" ].compact.map(&:downcase).uniq
    end

    def client
      @client ||= Account::LogoFetcher::Client.new
    end
end
