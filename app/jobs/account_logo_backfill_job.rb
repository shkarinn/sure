# Nightly retry for accounts whose domain has no logo yet: new accounts whose
# first fetch failed, and accounts that had a domain before auto-fetching existed.
class AccountLogoBackfillJob < ApplicationJob
  queue_as :scheduled

  def perform
    Account.visible
      .where.not(institution_domain: [ nil, "" ])
      .where(prefer_brandfetch_logo: false)
      .where.missing(:logo_attachment)
      .find_each { |account| AccountLogoFetchJob.perform_later(account) }
  end
end
