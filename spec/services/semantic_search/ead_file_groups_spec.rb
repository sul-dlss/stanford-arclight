# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::EadFileGroups do
  describe '.call' do
    it 'groups files by their immediate parent directory' do
      files = ['data/eal/eal0002.xml', 'data/cubberley/cubb00002.xml', 'data/eal/eal0003.xml']

      expect(described_class.call(files)).to eq(
        'eal' => ['data/eal/eal0002.xml', 'data/eal/eal0003.xml'],
        'cubberley' => ['data/cubberley/cubb00002.xml']
      )
    end

    it 'keeps every repository in its own group, so each gets its own REPOSITORY_ID' do
      files = %w[data/ars/a.xml data/chs/b.xml data/uarc/c.xml data/ars/d.xml]

      groups = described_class.call(files)

      expect(groups.keys).to contain_exactly('ars', 'chs', 'uarc')
      expect(groups['ars']).to eq(%w[data/ars/a.xml data/ars/d.xml])
    end

    it 'handles absolute paths' do
      expect(described_class.call(['/srv/data/manuscripts/m0001.xml']))
        .to eq('manuscripts' => ['/srv/data/manuscripts/m0001.xml'])
    end

    it 'returns an empty hash for no files' do
      expect(described_class.call([])).to eq({})
    end
  end

  describe '.repository_code' do
    it 'is the parent directory name' do
      expect(described_class.repository_code('data/uarc/sc0340.xml')).to eq('uarc')
    end
  end

  describe '.configured?' do
    it 'is true for a slug present in config/repositories.yml' do
      expect(described_class.configured?('ars')).to be true
    end

    it 'is false for a directory with no configured repository' do
      expect(described_class.configured?('no-such-repo')).to be false
    end
  end
end
