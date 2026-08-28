# frozen_string_literal: true

module Avatarable
  extend ActiveSupport::Concern
  include Rails.application.routes.url_helpers

  ALLOWED_AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  included do
    has_one_attached :avatar
    validate :acceptable_avatar, if: -> { avatar.changed? }
    after_save :fetch_external_avatar
  end

  def avatar_url
    return url_for(avatar.representation(resize_to_fill: [250, nil])) if avatar.attached? && avatar.representable?

    ''
  end

  def fetch_external_avatar
    if is_a?(User)
      nextcloud_username = custom_attributes&.dig('nextcloud_username')

      if nextcloud_username.present?
        return unless saved_changes.key?(:email) || saved_changes.key?(:custom_attributes)

        avatar_url = "https://cloud.soatrix.com/avatar/#{ERB::Util.url_encode(nextcloud_username)}/512/dark"
        Avatar::AvatarFromUrlJob.perform_later(self, avatar_url)
        return
      end
    end

    fetch_avatar_from_gravatar
  end

  def fetch_avatar_from_gravatar
    return unless saved_changes.key?(:email)
    return if email.blank?

    # Incase avatar_url is supplied, we don't want to fetch avatar from gravatar
    # So we will wait for it to be processed
    Avatar::AvatarFromGravatarJob.set(wait: 30.seconds).perform_later(self, email)
  end

  def acceptable_avatar
    return unless avatar.attached?

    errors.add(:avatar, 'is too big') if avatar.byte_size > 15.megabytes

    errors.add(:avatar, 'filetype not supported') unless ALLOWED_AVATAR_CONTENT_TYPES.include?(avatar.content_type)
  end
end
