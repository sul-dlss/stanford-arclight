# frozen_string_literal: true

Arclight::Parents.class_eval do
  # Let eadid be nil since we're not using it in this context to form ids
  # and we have cases where it is missing from Stanford EADs.
  def eadid; end
end
