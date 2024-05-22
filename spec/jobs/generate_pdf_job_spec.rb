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
  let(:stdout_double) { instance_double('IO') }
  let(:stderr_double) { instance_double('IO') }
  let(:wait_thread) { instance_double('Thread', join: nil, value: p) }
  let(:process_status) { instance_double('Process::Status') }
  let(:pdf_reader) { instance_double(PDF::Reader) }
  let(:pages) { instance_double(Enumerable) }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:read).with(file_path).and_return(fake_ead)
    allow(stdin_double).to receive(:write)
    allow(stdin_double).to receive(:close)
    allow(stdout_double).to receive(:read)
    allow(stderr_double).to receive(:read)
    allow(Open3).to receive(:popen3).and_yield(stdin_double, stdout_double, stderr_double)
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
    context 'when skip_existing is true and a valid PDF exists' do
      it 'does not create a new PDF' do
        allow(File).to receive(:exist?).with(pdf_file_path).and_return(true)
        allow(PDF::Reader).to receive(:new).with(pdf_file_path).and_return(pdf_reader)
        allow(pdf_reader).to receive(:pages).and_return(pages)
        allow(pages).to receive(:any?).and_return(true)
        described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: true)
        expect(Open3).not_to have_received(:popen3)
      end
    end

    context 'when skip_existing is true and an invalid PDF exists' do
      it 'does create a new PDF' do
        allow(File).to receive(:exist?).with(pdf_file_path).and_return(true)
        allow(PDF::Reader).to receive(:new).with(pdf_file_path).and_return(pdf_reader)
        allow(pdf_reader).to receive(:pages).and_return(pages)
        allow(pages).to receive(:any?).and_return(false, true)

        described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: true)
        expect(Open3).to have_received(:popen3)
      end
    end

    context 'when skip_existing is false and the PDF exists' do
      it 'creates a new PDF using properly namespaced XML' do
        allow(File).to receive(:exist?).with(pdf_file_path).and_return(true)
        allow(PDF::Reader).to receive(:new).with(pdf_file_path).and_return(pdf_reader)
        allow(pdf_reader).to receive(:pages).and_return(pages)
        allow(pages).to receive(:any?).and_return(true)
        described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: false)

        expect(Open3).to have_received(:popen3).with(
          "java -jar #{Settings.pdf_generation.saxon_path} -s:- "\
          "-xsl:#{Settings.pdf_generation.ead_to_fo_xsl_path} " \
          "pdf_image=#{Settings.pdf_generation.logo_path} | " \
          "#{Settings.pdf_generation.fop_path} -q -c #{Settings.pdf_generation.fop_config_path} " \
          "- -pdf #{pdf_file_path}"
        )
        expect(stdin_double).to have_received(:write).with(a_string_including('urn:isbn:1-931666-22-9'))
      end
    end

    context 'when the PDF file is not generated' do
      it 'raises a GeneratePdfError with the EAD file path' do
        allow(PDF::Reader).to receive(:new).with(pdf_file_path).and_raise(PDF::Reader::MalformedPDFError)
        allow(stderr_double).to receive(:read).and_return('')
        expect do
          described_class.perform_now(file_path:, file_name:, data_dir:, skip_existing: false)
        end.to raise_error(GeneratePdfJob::GeneratePdfError, /#{file_path}/)
      end
    end
  end
end
# rubocop: enable RSpec/MultipleMemoizedHelpers
