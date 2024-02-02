output "config" {
  description = "Configuration credentials for connecting to openid client"
  value = local.auth_enabled ? {
    enabled       = true
    client_id     = keycloak_openid_client.this[0].client_id
    issuer_url    = "${local.external_url}realms/${local.realm_id}"
    discovery_url = "${local.external_url}realms/${local.realm_id}/.well-known/openid-configuration"
    auth_url      = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/auth"
    token_url     = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/token"
    jwks_url      = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/certs"
    logout_url    = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/logout"
    userinfo_url  = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/userinfo"
  } : {
    enabled       = false
    client_id     = ""
    issuer_url    = ""
    discovery_url = ""
    auth_url      = ""
    token_url     = ""
    jwks_url      = ""
    logout_url    = ""
    userinfo_url  = ""
  }
  sensitive = false
}
