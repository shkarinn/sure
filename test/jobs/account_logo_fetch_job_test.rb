require "test_helper"

class AccountLogoFetchJobTest < ActiveJob::TestCase
  setup do
    @account = accounts(:depository)
    @account.update_columns(institution_domain: "tbank.ru")
  end

  test "picks a logo automatically" do
    Account::LogoFetcher.any_instance.expects(:fetch).with(auto: true).returns(true)

    AccountLogoFetchJob.perform_now(@account)
  end

  test "leaves a logo the user uploaded" do
    @account.logo.attach(io: file_fixture("square-placeholder.png").open, filename: "mine.png")
    Account::LogoFetcher.any_instance.expects(:fetch).never

    AccountLogoFetchJob.perform_now(@account)
  end
end
