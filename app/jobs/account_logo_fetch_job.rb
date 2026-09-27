class AccountLogoFetchJob < ApplicationJob
  queue_as :low_priority

  def perform(account)
    return unless account.logo_auto_fetchable?

    Account::LogoFetcher.new(account).fetch(auto: true)
  end
end
