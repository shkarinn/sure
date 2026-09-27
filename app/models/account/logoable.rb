# The account's icon: an uploaded or fetched logo, the Brandfetch logo for the
# institution domain, or the provider's logo, in that order unless the user
# chose Brandfetch over the stored logo.
module Account::Logoable
  extend ActiveSupport::Concern

  LOGO_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp image/vnd.microsoft.icon image/x-icon].freeze
  LOGO_MAX_SIZE = 1.megabyte

  included do
    has_one_attached :logo, dependent: :purge_later
    validate :logo_is_small_raster_image, if: -> { logo.attached? }

    after_commit :fetch_logo_later, if: -> { saved_change_to_institution_domain? && read_attribute(:institution_domain).present? }
  end

  def logo_url
    if prefer_brandfetch_logo? && brandfetch_logo_url
      brandfetch_logo_url
    else
      stored_logo_url || brandfetch_logo_url || provider&.logo_url.presence
    end
  end

  # A rejected upload re-rendered in the form is attached but unsaved and has no URL yet.
  def stored_logo_url
    Rails.application.routes.url_helpers.rails_blob_path(logo, only_path: true) if logo.attached? && logo.blob.persisted?
  end

  def brandfetch_logo_url
    return if institution_domain.blank? || Setting.brand_fetch_client_id.blank?

    logo_size = Setting.brand_fetch_logo_size
    "https://cdn.brandfetch.io/#{institution_domain}/icon/fallback/lettermark/w/#{logo_size}/h/#{logo_size}?c=#{Setting.brand_fetch_client_id}"
  end

  # Where the stored logo came from: a favicon service, "appstore" or
  # "googleplay", or nil for an upload.
  def logo_source
    logo.blob.metadata["logo_source"] if logo.attached?
  end

  # The Account::LogoFetcher key of the stored logo, e.g. "appstore:123".
  def logo_key
    logo.blob.metadata["logo_key"] || logo_source if logo.attached?
  end

  def logo_auto?
    logo.attached? && logo.blob.metadata["logo_auto"] == true
  end

  # Sure only picks logos nobody chose: an empty slot or its own earlier pick.
  def logo_auto_fetchable?
    institution_domain.present? && !prefer_brandfetch_logo? && (!logo.attached? || logo_auto?)
  end

  private
    # SVG is excluded: it can carry scripts and is not served inline anyway.
    def logo_is_small_raster_image
      unless logo.content_type.in?(LOGO_CONTENT_TYPES)
        errors.add(:logo, :invalid_content_type)
      end

      if logo.blob.byte_size > LOGO_MAX_SIZE
        errors.add(:logo, :too_large, max_size: LOGO_MAX_SIZE / 1.megabyte)
      end
    end

    def fetch_logo_later
      AccountLogoFetchJob.perform_later(self)
    end
end
