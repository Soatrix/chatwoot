# Enterprise Edition SAML SSO Provider
# This initializer adds SAML authentication support for Enterprise customers

# Authentik exposes a unified SAML endpoint for both SSO and SLO on newer
# versions, while its legacy binding-specific endpoints remain supported.
# Resolve the SLO endpoint from the SAML settings we already store without
# requiring another database field or a network metadata lookup on logout.
AUTHENTIK_SAML_SLO_URL_RESOLVER = lambda do |settings|
  entity_id = settings.idp_entity_id.to_s
  sso_url = settings.sso_url.to_s

  if entity_id.match?(%r{/application/saml/[^/]+/metadata/?\z})
    entity_id.sub(%r{/metadata/?\z}, '/')
  elsif sso_url.match?(%r{/application/saml/[^/]+/sso/binding/(?:redirect|post|init)/?\z})
    sso_url.sub(%r{/sso/binding/(?:redirect|post|init)/?\z}, '/slo/binding/redirect/')
  elsif sso_url.match?(%r{/application/saml/[^/]+/?\z})
    sso_url
  end
end

# SAML setup proc for multi-tenant configuration
SAML_SETUP_PROC = proc do |env|
  request = ActionDispatch::Request.new(env)

  # Extract account_id from various sources
  account_id = request.params['account_id'] ||
               env['omniauth.params']&.dig('account_id')
  relay_state = request.params['RelayState'] || ''

  if account_id
    # Keep SAML request context in OmniAuth env so the callback can be processed
    # without depending on the Rails session cookie.
    env['omniauth.params'] ||= {}
    env['omniauth.params']['account_id'] = account_id
    env['omniauth.params']['RelayState'] = relay_state

    # Find SAML settings for this account
    settings = AccountSamlSettings.find_by(account_id: account_id)

    if settings
      # Configure the strategy options dynamically
      strategy_options = env['omniauth.strategy'].options
      strategy_options[:idp_sso_service_url_runtime_params] = { RelayState: :RelayState }
      strategy_options[:assertion_consumer_service_url] = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/saml/callback?account_id=#{account_id}"
      strategy_options[:sp_entity_id] = settings.sp_entity_id
      strategy_options[:idp_entity_id] = settings.idp_entity_id
      strategy_options[:idp_sso_service_url] = settings.sso_url
      strategy_options[:idp_cert] = settings.certificate
      strategy_options[:name_identifier_format] = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'

      # omniauth-saml already stores the NameID and SessionIndex in the Rails
      # session after a successful assertion. Enabling these options activates
      # its built-in /omniauth/saml/spslo and /omniauth/saml/slo handlers.
      strategy_options[:idp_slo_service_url] = AUTHENTIK_SAML_SLO_URL_RESOLVER.call(settings)
      strategy_options[:idp_slo_service_binding] = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
      strategy_options[:single_logout_service_url] = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/saml/slo?account_id=#{account_id}"
      strategy_options[:single_logout_service_binding] = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
      strategy_options[:slo_enabled] = strategy_options[:idp_slo_service_url].present?
      strategy_options[:slo_default_relay_state] = '/app/login'
    else
      # Set a dummy certificate to avoid the error
      env['omniauth.strategy'].options[:idp_cert] = 'DUMMY'
      env['omniauth.strategy'].options[:idp_slo_service_url] = nil
    end
  else
    # Set a dummy certificate to avoid the error
    env['omniauth.strategy'].options[:idp_cert] = 'DUMMY'
    env['omniauth.strategy'].options[:idp_slo_service_url] = nil
  end
end

Rails.application.config.middleware.use OmniAuth::Builder do
  # SAML provider with setup phase for multi-tenant configuration
  provider :saml, setup: SAML_SETUP_PROC
end
