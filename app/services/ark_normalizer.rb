# frozen_string_literal: true

# This class normalizes ARK IDs to the format needed to match with ARKs in Solr
class ArkNormalizer
  NAAN = Settings.ark_naan

  # Adds hyphens to the UUID if missing, preserving the shoulder
  # rubocop:disable Metrics/MethodLength
  def self.normalize(ark)
    match = ark.match(%r{\Aark:/#{NAAN}/([a-z]\d)([0-9a-f]{32})\z}io)
    return ark unless match

    shoulder = match[1]
    uuid = match[2]

    hyphenated_uuid = [
      uuid[0, 8],
      uuid[8, 4],
      uuid[12, 4],
      uuid[16, 4],
      uuid[20, 12]
    ].join('-')

    "ark:/#{NAAN}/#{shoulder}#{hyphenated_uuid}"
  end
  # rubocop:enable Metrics/MethodLength
end
