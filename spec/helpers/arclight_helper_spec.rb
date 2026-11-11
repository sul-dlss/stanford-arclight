# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ArclightHelper do
  describe '#render_html_tags' do
    subject(:html) { Capybara.string(helper.render_html_tags(value: [value])) }

    context 'with a bare URL in the text' do
      let(:value) { '<p>See the pamphlets: https://searchworks.stanford.edu/view/4083614.</p>' }

      it 'links the URL, leaving trailing punctuation out of the link' do
        expect(html).to have_link 'https://searchworks.stanford.edu/view/4083614',
                                  href: 'https://searchworks.stanford.edu/view/4083614'
        expect(html).to have_text 'See the pamphlets: https://searchworks.stanford.edu/view/4083614.'
      end
    end

    context 'with an extref that has a URL as its text but no href' do
      let(:value) { '<p>Ruth Asawa papers (M1585): <extref>https://searchworks.stanford.edu/view/9615156</extref></p>' }

      it 'links the URL' do
        expect(html).to have_link 'https://searchworks.stanford.edu/view/9615156',
                                  href: 'https://searchworks.stanford.edu/view/9615156'
      end
    end

    context 'with a retired library URL that now redirects to the library home page' do
      let(:value) { '<p>See http://library.stanford.edu/depts/spc/pubserv/permissions.html.</p>' }

      it 'links to the current page, keeping the URL text as written' do
        expect(html).to have_link 'http://library.stanford.edu/depts/spc/pubserv/permissions.html',
                                  href: 'https://library.stanford.edu/special-collections-policies'
      end
    end

    context 'with quotes and escaped characters around a bare URL' do
      let(:value) { %(<p>Fish &amp; chips at &lt;"https://a.org/x?b=1&amp;c=2"&gt; and 'https://a.org/y' now</p>) }

      it 'links the URLs and keeps the surrounding text intact' do
        expect(html).to have_link 'https://a.org/x?b=1&c=2', href: 'https://a.org/x?b=1&c=2'
        expect(html).to have_link 'https://a.org/y', href: 'https://a.org/y'
        expect(html).to have_text %(Fish & chips at <"https://a.org/x?b=1&c=2"> and 'https://a.org/y' now)
      end
    end

    context 'with a retired library URL already in an href' do
      let(:value) { '<p><extref href="http://library.stanford.edu/depts/spc/spc.html">Special Collections</extref></p>' }

      it 'points the link to the current page' do
        expect(html).to have_link 'Special Collections', href: 'https://library.stanford.edu/libraries/special-collections'
      end
    end

    context 'with a bare URL inside a bibref' do
      let(:value) { '<p><bibref>"Our history," retrieved May 2011 from http://www.aclunc.org/about/history/index.shtml</bibref></p>' }

      it 'links the URL' do
        expect(html).to have_link 'http://www.aclunc.org/about/history/index.shtml'
      end
    end

    context 'with a URL that is already linked' do
      let(:value) { '<p><extref href="https://oac.cdlib.org/findaid/ark:/13030/tf109n9832">https://oac.cdlib.org/findaid/ark:/13030/tf109n9832</extref></p>' }

      it 'does not add a second link' do
        expect(html).to have_link count: 1
      end
    end
  end
end
