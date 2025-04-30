# frozen_string_literal: true

# Component used to comply with SUL component-library Alert styles
class AlertComponent < Blacklight::System::FlashMessageComponent
  attr_reader :message, :type

  def initialize(message:, type:)
    super
    @message = message
    @type = type
  end

  def icon
    # Fallback is BootstrapInfoCircleFillComponent
    {
      'info' => Blacklight::Icons::BootstrapInfoCircleFillComponent,
      'alert' => Blacklight::Icons::BootstrapInfoCircleFillComponent,
      'notice' => Blacklight::Icons::BootstrapInfoCircleFillComponent,
      'warning' => Blacklight::Icons::BootstrapExclamationTriangleFillComponent,
      'danger' => Blacklight::Icons::BootstrapExclamationTriangleFillComponent,
      'success' => Blacklight::Icons::BootstrapCheckCircleFillComponent,
      'note' => Blacklight::Icons::BootstrapExclamationCircleFillComponent
    }.fetch(type.to_s, Blacklight::Icons::BootstrapInfoCircleFillComponent)
  end
end
