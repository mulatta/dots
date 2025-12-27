# Verify Vultr API Token (via account endpoint)
GET https://api.vultr.com/v2/account
Authorization: Bearer {{VULTR_API}}

HTTP *
[Captures]
status_code: status
response: body
