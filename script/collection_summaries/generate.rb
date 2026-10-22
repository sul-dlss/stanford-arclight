# frozen_string_literal: true

# Writes one AI summary JSON file per EAD, for the "About this collection" block.
#
#   bundle exec ruby script/collection_summaries/generate.rb DATA_DIR OUT_DIR FILE ...
#
# FILE is a path relative to DATA_DIR, such as manuscripts/m0733.xml. The output
# goes to OUT_DIR/manuscripts/m0733.json. A file whose EAD, prompt, and model are
# unchanged is skipped; set FORCE=1 to write it again. Set RECHECK=1 to run the
# checks again on the saved summaries, without a model call.
#
# When the checks find problems, the model gets one chance to correct them.
# The first draft and its problems stay in the file as first_draft.
# See script/collection_summaries/DECISIONS.md for why.

require 'digest'
require 'fileutils'
require 'json'
require 'time'
require_relative '../../app/services/collection_summary/organization'
require_relative '../../app/services/collection_summary/evidence'
require_relative '../../app/services/collection_summary/check'
require_relative '../../app/services/semantic_search/chat_completion_service'

MODEL = ENV.fetch('COLLECTION_SUMMARY_MODEL', 'gemini-3.8-flash')
PROMPT = File.read(File.join(__dir__, 'prompt.md')).sub('{{LABELS}}', CollectionSummary::Check::LABELS.join('; '))
PROMPT_SHA = Digest::SHA256.hexdigest(PROMPT)

$stdout.sync = true # progress shows in a log during a long batch
data_dir, out_dir, *files = ARGV
abort 'usage: generate.rb DATA_DIR OUT_DIR FILE ...' if files.empty?
client = SemanticSearch::ChatCompletionService.new(timeout: 900)

def unchanged?(out_path, ead_sha)
  return false if ENV['FORCE'] || !File.exist?(out_path)

  old = JSON.parse(File.read(out_path))
  old.values_at('ead_sha256', 'prompt_sha256', 'model') == [ead_sha, PROMPT_SHA, MODEL] && !old['error']
end

def checked(evidence, summary)
  cited = (summary['statements'].to_a + summary['highlights'].to_a).flat_map { |entry| Array(entry['cites']) }
  refs = cited.grep(Integer).uniq.sort.to_h { |n| [n, { ref: evidence.ref(n), title: evidence.title(n) }] }
  { summary:, refs:, problems: CollectionSummary::Check.new(evidence, summary).problems }
end

def recheck(ead_path, out_path)
  record = JSON.parse(File.read(out_path))
  return 'no summary to check' unless record['summary']

  record.merge!(checked(CollectionSummary::Evidence.from_file(ead_path), record['summary']).transform_keys(&:to_s))
  File.write(out_path, JSON.pretty_generate(record))
  "#{record['problems'].size} problems, rechecked"
end

# The gateway limits tokens per minute for each key, and a large EAD can use
# half of that limit, so a 429 waits for the limit to reset.
def complete(client, messages, tries: 5)
  client.complete(messages, model: MODEL, max_tokens: 16_000, temperature: 0.2)
rescue SemanticSearch::ChatCompletionService::ApiError => e
  raise unless e.message.include?('returned 429') && (tries -= 1).positive?

  puts '  rate limited, waiting 60 s'
  sleep 60
  retry
end

def revision(problems)
  "The checks found these problems in your summary:\n#{problems.map { |problem| "- #{problem}" }.join("\n")}\n\n" \
    'Correct them and return the whole summary as JSON only. Keep the parts that follow the rules.'
end

def parse(raw)
  JSON.parse(raw.strip.sub(/\A```(?:json)?\s*/, '').sub(/\s*```\z/, ''))
end

files.each do |file|
  ead_path = File.join(data_dir, file)
  out_path = File.join(out_dir, file.sub(/\.xml\z/, '.json'))
  next puts("#{file}: #{recheck(ead_path, out_path)}") if ENV['RECHECK'] && File.exist?(out_path)

  ead_sha = Digest::SHA256.file(ead_path).hexdigest
  next puts("#{file}: unchanged, skipped") if unchanged?(out_path, ead_sha)

  record = { file:, model: MODEL, prompt_sha256: PROMPT_SHA, ead_sha256: ead_sha, generated_at: Time.now.utc.iso8601 }
  started = Time.now
  begin
    evidence = CollectionSummary::Evidence.from_file(ead_path)
    record[:input_bytes] = evidence.text.bytesize
    messages = [{ role: 'system', content: PROMPT }, { role: 'user', content: evidence.text }]
    raw = complete(client, messages)
    result = checked(evidence, parse(raw))
    if result[:problems].any?
      revised = complete(client, messages + [{ role: 'assistant', content: raw },
                                             { role: 'user', content: revision(result[:problems]) }])
      record[:first_draft] = result.slice(:summary, :problems)
      result = checked(evidence, parse(revised))
    end
    record.merge!(result)
  # One bad EAD or reply must not stop a long batch; the error goes in its file.
  rescue StandardError => e
    record.merge!(error: "#{e.class}: #{e.message}", raw:)
  end
  record[:seconds] = (Time.now - started).round(1)

  FileUtils.mkdir_p(File.dirname(out_path))
  File.write(out_path, JSON.pretty_generate(record))
  puts "#{file}: #{record[:error] || "#{record[:problems].size} problems"} (#{record[:seconds]} s)"
end
