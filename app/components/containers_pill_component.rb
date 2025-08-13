# frozen_string_literal: true

# Component for rendering the container information
class ContainersPillComponent < ViewComponent::Base
  def initialize(document:, compact: false)
    @document = document
    @compact = compact
    super()
  end

  def containers
    @document.containers.join(', ')
  end

  def render?
    @document.containers.any? && !@compact
  end
end
