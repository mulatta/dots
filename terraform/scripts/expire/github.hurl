# Verify GitHub Token
# Fine-grained PAT returns expiration in response header
GET https://api.github.com/user
Authorization: Bearer {{GITHUB_TOKEN}}
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28

HTTP *
[Captures]
status_code: status
response: body
# Note: expires header only present for Fine-grained PATs, not OAuth
