# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Aspace::Repository do
  subject(:repository) do
    described_class.new(repo_code: 'ARS', uri: '/resources/11')
  end

  it { expect(repository.id).to eq '11' }
  it { expect(repository.code).to eq 'ars' }
  it { expect(repository.uri).to eq '/resources/11' }
  it { expect(repository.harvestable?).to be true }
end
