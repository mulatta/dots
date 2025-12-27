# Get Cloudflare Account Info
GET https://api.cloudflare.com/client/v4/accounts
Authorization: Bearer {{CLOUDFLARE_API_TOKEN}}

HTTP *
[Captures]
status_code: status
response: body
