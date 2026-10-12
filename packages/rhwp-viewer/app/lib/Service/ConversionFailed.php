<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Service;

use RuntimeException;
use Throwable;

final class ConversionFailed extends RuntimeException {
    public const REASON_MISSING_EXECUTABLE = 'missing_executable';
    public const REASON_NON_ZERO_EXIT = 'non_zero_exit';
    public const REASON_NO_OUTPUT = 'no_output';
    public const REASON_UNSUPPORTED_DOCUMENT = 'unsupported_document';
    public const REASON_TIMEOUT = 'timeout';
    public const REASON_EXECUTION_ERROR = 'execution_error';

    private function __construct(
        private string $reason,
        string $message,
        private ?int $exitCode = null,
        private string $stdout = '',
        private string $stderr = '',
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, 0, $previous);
    }

    public static function missingExecutable(string $path): self {
        return new self(
            self::REASON_MISSING_EXECUTABLE,
            sprintf('RHWP executable is missing or not executable: %s', $path),
        );
    }

    public static function nonZeroExit(int $exitCode, string $stdout, string $stderr): self {
        return new self(
            self::REASON_NON_ZERO_EXIT,
            sprintf('RHWP exited with status %d.', $exitCode),
            $exitCode,
            $stdout,
            $stderr,
        );
    }

    public static function timeout(float $timeoutSeconds, string $stdout, string $stderr): self {
        return new self(
            self::REASON_TIMEOUT,
            sprintf('RHWP timed out after %.3f seconds.', $timeoutSeconds),
            null,
            $stdout,
            $stderr,
        );
    }

    public static function noOutput(string $stdout, string $stderr): self {
        return new self(
            self::REASON_NO_OUTPUT,
            'RHWP did not produce any SVG pages.',
            null,
            $stdout,
            $stderr,
        );
    }

    public static function unsupportedDocument(string $name): self {
        return new self(
            self::REASON_UNSUPPORTED_DOCUMENT,
            sprintf('Unsupported RHWP document type: %s', $name),
        );
    }

    public static function executionError(string $message, ?Throwable $previous = null): self {
        return new self(self::REASON_EXECUTION_ERROR, $message, null, '', '', $previous);
    }

    public function getReason(): string {
        return $this->reason;
    }

    public function getExitCode(): ?int {
        return $this->exitCode;
    }

    public function getStdout(): string {
        return $this->stdout;
    }

    public function getStderr(): string {
        return $this->stderr;
    }
}
