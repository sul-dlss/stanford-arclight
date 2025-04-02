# frozen_string_literal: true

# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever
job_type :runner, "cd :path && RAILS_LOG_LEVEL=warn bin/rails runner -e :environment ':task' :output"

every :day do
  runner 'DownloadEadJob.enqueue_all_updated'
end

every :day, at: '3:00 am' do
  runner 'GeneratePdfJob.enqueue_all_missing_and_invalid'
end

every 6.hours do
  runner 'DeleteEadJob.enqueue_all'
end

every :day, at: '4:00 am' do
  rake 'stanford_arclight:prune_guest_user_data[12]'
end

every :day, at: '5:00 am' do
  rake 'stanford_arclight:prune_search_data[6]'
end
