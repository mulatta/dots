# Verify Cloudflare API Token
GET https://api.cloudflare.com/client/v4/user/tokens/verify
Authorization: Bearer {{CLOUDFLARE_API_TOKEN}}

HTTP *
[Captures]
status_code: status
response: body
