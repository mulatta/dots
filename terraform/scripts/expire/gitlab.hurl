# Verify GitLab Token
GET https://gitlab.com/api/v4/personal_access_tokens/self
PRIVATE-TOKEN: {{GITLAB_TOKEN}}

HTTP *
[Captures]
status_code: status
response: body
