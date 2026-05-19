# Get Vultr Account Info (includes balance and pending charges)
GET https://api.vultr.com/v2/account
Authorization: Bearer {{VULTR_API}}

HTTP *
[Captures]
status_code: status
response: body
