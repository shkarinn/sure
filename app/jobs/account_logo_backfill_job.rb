# Nightly retry for accounts whose domain has no logo yet: new accounts whose
# first fetch failed, and accounts that had a domain before auto-fetching existed.
class AccountLogoBackfillJob < ApplicationJob
  queue_as :scheduled

  # The iTunes Search API allows about 20 requests a minute, and each fetch
  # makes up to three of them.
  SPACING = 20.seconds

  def perform
    Account.visible
      .where.not(institution_domain: [ nil, "" ])
      .where(prefer_brandfetch_logo: false)
      .where.missing(:logo_attachment)
      .find_each.with_index { |account, index| AccountLogoFetchJob.set(wait: index * SPACING).perform_later(account) }
  end
end
