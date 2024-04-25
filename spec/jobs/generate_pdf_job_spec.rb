# frozen_string_literal: true

require 'rails_helper'

# rubocop: disable RSpec/MultipleMemoizedHelpers
RSpec.describe GeneratePdfJob do
  let(:file_path) { '/repo/ARS.0043_ead.xml' }
  let(:file_name) { 'ARS.0043_ead.xml' }
  let(:pdf_file_name) { 'ARS.0043_ead.pdf' }
  let(:pdf_file_path) { '/repo/ARS.0043_ead.pdf' }
  let(:data_dir) { '/repo' }
  let(:fake_ead) { '<?xml version="1.0"?><ead></ead></xml>' }
  let(:stdin_double) { instance_double('IO') }
  let(:wait_thread) { instance_double('Thread', join: nil, value: p) }
  let(:process_status) { instance_double('Process::Status') }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:read).with(file_path).and_return(fake_ead)
    allow(stdin_double).to receive(:write)
    allow(stdin_double).to receive(:close)
    allow(Open3).to receive(:pipeline_w).and_return([stdin_double, [wait_thread]])
  end

  describe '.enqueue_all' do
    before do
      allow(Dir).to receive(:glob).and_yield('/repo/ead1.xml').and_yield('/repo/ead2.xml')
    end

    it 'enqueues jobs for all XML files in the directory' do
      expect do
        described_class.enqueue_all(data_dir: '/repo', skip_existing: false)
      end.to enqueue_job(described_class).exactly(2).times
    end
  end

  describe '#perform' do
    context 'when skip_existing is true and the PDF exists' do
      it 'does not create a new PDF' do
        allow(File).to receive(:exist?).with(pdf_file_path).and_return(true)
        described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: true)
        expect(Open3).not_to have_received(:pipeline_w)
      end
    end

    context 'when skip_existing is false and the PDF exists' do
      it 'creates a new PDF using properly namespaced XML' do
        allow(File).to receive(:exist?).with(pdf_file_path).and_return(true)
        described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: false)

        expect(Open3).to have_received(:pipeline_w).with(
          "java -jar #{Settings.pdf_generation.saxon_path} -s:- "\
          "-xsl:#{Settings.pdf_generation.ead_to_fo_xsl_path} " \
          "pdf_image=#{Settings.pdf_generation.logo_path}",
          "#{Settings.pdf_generation.fop_path} -q -c #{Settings.pdf_generation.fop_config_path} " \
          "- -pdf #{pdf_file_path}"
        )
        expect(stdin_double).to have_received(:write).with(a_string_including('urn:isbn:1-931666-22-9'))
      end
    end

    context 'when the PDF file is not generated' do
      it 'raises a GeneratePdfError' do
        allow(File).to receive(:exist?).with(pdf_file_path).and_return(false)
        expect do
          described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: false)
        end.to raise_error(GeneratePdfJob::GeneratePdfError)
      end
    end
  end
end
# rubocop: enable RSpec/MultipleMemoizedHelpers
