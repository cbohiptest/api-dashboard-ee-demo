require 'net/http'
require 'json'

# Set the following constants with your data
PROJECT_ID = 23
ACCESS_TOKEN = '9aRgRLnbR8JM6r4KDR0pKQ'
CLIENT_ID = 'IPSoe-Et9NjdllsVW-Vsfg'
UID = 'celine.bon@hiptest.net'

PROJECT_URL = "http://localhost:3000/api/projects/#{PROJECT_ID}"

def get_URL(route)
  uri = URI("#{PROJECT_URL}/#{route}")
  result = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new uri
    request['Accept'] = "application/vnd.api+json; version=1"
    request['access-token'] = ACCESS_TOKEN
    request['client'] = CLIENT_ID
    request['uid'] = UID
    http.request request
  end

  if result and result.is_a?(Net::HTTPOK)
    response = JSON.parse(result.body)
    return response
  end
  nil
end

def request_test_runs
  response = get_URL("test_runs")

  return nil if response.nil?
  # To return an array containing only names and statusese of test runs
  return response['data'].collect do |test_run|
    {
      'id' => test_run['id'],
      'name' => test_run['attributes']['name']
    }
  end
end

def request_environments(test_run)
  response = get_URL("test_runs/#{test_run['id']}/execution_environments")

  return nil if response.nil?
  # To return an array containing only names and statusese of test runs
  return response['data'].collect do |ee|
    {
      'id' => ee['id'],
      'name' => ee['attributes']['name']
    }
  end
end

def request_results(test_run, ee)
  response = get_URL("test_runs/#{test_run['id']}/execution_environments/#{ee['id']}/builds/current?include=test-results")

  return nil if response.nil?
  # To return an array containing only names and statusese of test runs
  return response['included'].collect do |result|
    result['attributes']['status']
  end
end

def summarize_results(results)
  summarized_results = Hash.new(0)

  results.each do |result|
    summarized_results[result] += 1
  end

  summarized_results
end

# This method is in charge of returning the most
# valuable status for the given statuses.
#
# It's up to you to define here which status you want your
# dashboard to show depending the statuses of a test run
def get_status_text(statuses)

  return "Failed" if statuses['failed'] > 0
  return "Blocked" if statuses['blocked'] > 0
  return "Skipped" if statuses['skipped'] > 0
  return "Work in progress" if statuses['wip'] > 0 || statuses['undefined'] > 0
  return "Retest" if statuses['retest'] > 0
  return "Passed" if statuses['passed'] > 0

  return "Unknown"

end

# This will simply concatenate the statuses
# into a single string
def get_status_details(statuses)

  return statuses.map { |key, value|
    "#{key}: #{value}" if value > 0
  }.join(' ')

end

def get_tr_status_text(statuses)
  get_status_text(summarize_results(statuses.values.flatten))
end

# Every 30 seconds the dashboard will fetch statuses from Hiptest
# then refresh the tiles accordingly
SCHEDULER.every '2s' do

  test_runs = request_test_runs

  unless test_runs.nil?

    test_runs.each_with_index do |test_run, index|
      environments = request_environments(test_run)

      results = Hash.new

      environments.each do |ee|
        results[ee['name']] = request_results(test_run, ee)
        summarized = summarize_results(results[ee['name']])

        send_event(
          "tr-#{test_run['id']}-#{ee['name']}",
          {
            title: "#{test_run['name']} on #{ee['name']}",
            text: get_status_text(summarized),
            moreinfo: get_status_details(summarized)
          }
        )
      end

      send_event(
        "tr-#{test_run['id']}",
        {
          title: test_run['name'],
          text: get_tr_status_text(results),
          moreinfo: ''
        })
    end
  end
end