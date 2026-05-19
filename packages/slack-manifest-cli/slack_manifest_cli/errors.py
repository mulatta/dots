"""CLI error types."""


class CLIError(Exception):
    """Base error for expected CLI failures."""


class ConfigError(CLIError):
    """Configuration is missing or invalid."""


class ManifestError(CLIError):
    """Manifest file is missing or invalid."""


class SlackAPIError(CLIError):
    """Slack API returned an error."""
