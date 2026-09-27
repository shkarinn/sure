require "test_helper"

class AccountLogoBackfillJobTest < ActiveJob::TestCase
  test "queues a fetch for visible accounts with a domain and no logo" do
    Account.update_all(institution_domain: nil)
    without_logo = accounts(:depository)
    without_logo.update_columns(institution_domain: "tbank.ru")
    with_logo = accounts(:credit_card)
    with_logo.update_columns(institution_domain: "sberbank.ru")
    with_logo.logo.attach(io: file_fixture("square-placeholder.png").open, filename: "mine.png")

    AccountLogoBackfillJob.perform_now

    assert_enqueued_jobs 1, only: AccountLogoFetchJob
    assert_enqueued_with(job: AccountLogoFetchJob, args: [ without_logo ])
  end
end
