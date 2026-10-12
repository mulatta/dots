<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Service;

use OCA\RhwpViewer\AppInfo\Application;
use OCP\App\IAppManager;
use Throwable;

final class RhwpConverter {
    public function __construct(
        private IAppManager $appManager,
        private float $timeoutSeconds = 10.0,
    ) {
    }

    /**
     * @throws ConversionFailed
     */
    public function exportSvg(ResolvedFile $file): SvgExportResult {
        $workDir = $this->createWorkDir();
        $outputDir = $workDir . DIRECTORY_SEPARATOR . 'output';
        $inputName = 'input' . $this->documentSuffix($file);
        $inputPath = $workDir . DIRECTORY_SEPARATOR . $inputName;

        try {
            if (!mkdir($outputDir, 0700)) {
                throw ConversionFailed::executionError('Failed to create RHWP output directory.');
            }

            $this->copyInputFile($file, $inputPath);

            $result = $this->run(
                [$this->getCliPath(), 'export-svg', $inputName, '-o', 'output/'],
                $workDir,
            );

            $pages = $this->scanSvgPages($outputDir);
            if ($pages === []) {
                throw ConversionFailed::noOutput($result['stdout'], $result['stderr']);
            }

            return new SvgExportResult($workDir, $pages);
        } catch (ConversionFailed $error) {
            $this->removeTree($workDir);
            throw $error;
        } catch (Throwable $throwable) {
            $this->removeTree($workDir);
            throw ConversionFailed::executionError('Failed to export SVG pages.', $throwable);
        }
    }

    /**
     * @throws ConversionFailed
     */
    private function documentSuffix(ResolvedFile $file): string {
        $extension = strtolower(pathinfo($file->getName(), PATHINFO_EXTENSION));

        return match ($extension) {
            'hwp' => '.hwp',
            'hwpx' => '.hwpx',
            default => throw ConversionFailed::unsupportedDocument($file->getName()),
        };
    }

    /**
     * @throws ConversionFailed
     */
    private function copyInputFile(ResolvedFile $file, string $inputPath): void {
        $source = null;
        $target = null;

        try {
            $source = $file->getFile()->fopen('rb');
            if ($source === false) {
                throw ConversionFailed::executionError('Failed to open source file.');
            }

            $target = fopen($inputPath, 'wb');
            if ($target === false) {
                throw ConversionFailed::executionError('Failed to create RHWP input file.');
            }

            if (stream_copy_to_stream($source, $target) === false) {
                throw ConversionFailed::executionError('Failed to copy source file for conversion.');
            }
        } finally {
            if (is_resource($source)) {
                fclose($source);
            }
            if (is_resource($target)) {
                fclose($target);
            }
        }
    }

    /**
     * @return list<SvgPage>
     */
    private function scanSvgPages(string $outputDir): array {
        $paths = glob($outputDir . DIRECTORY_SEPARATOR . '*.svg');
        if ($paths === false) {
            return [];
        }

        sort($paths, SORT_STRING);

        $pages = [];
        foreach ($paths as $path) {
            if (!is_file($path)) {
                continue;
            }

            $bytes = filesize($path);
            if ($bytes === false) {
                continue;
            }

            $pages[] = new SvgPage(count($pages), $path, $bytes);
        }

        return $pages;
    }

    /**
     * @return array{stdout: string, stderr: string, exitCode: int}
     * @throws ConversionFailed
     */
    private function run(array $command, string $cwd): array {
        if ($this->timeoutSeconds <= 0.0) {
            throw ConversionFailed::executionError('RHWP timeout must be greater than zero.');
        }

        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        try {
            $process = proc_open(
                $command,
                $descriptors,
                $pipes,
                $cwd,
                null,
                ['bypass_shell' => true],
            );
        } catch (Throwable $throwable) {
            throw ConversionFailed::executionError('Failed to start RHWP.', $throwable);
        }

        if (!is_resource($process)) {
            throw ConversionFailed::executionError('Failed to start RHWP.');
        }

        fclose($pipes[0]);
        stream_set_blocking($pipes[1], false);
        stream_set_blocking($pipes[2], false);

        $stdout = '';
        $stderr = '';
        $exitCode = null;
        $timedOut = false;
        $startedAt = microtime(true);

        while (true) {
            $stdout .= $this->readPipe($pipes[1]);
            $stderr .= $this->readPipe($pipes[2]);

            $status = proc_get_status($process);
            if (!$status['running']) {
                $exitCode = $status['exitcode'];
                break;
            }

            if (microtime(true) - $startedAt >= $this->timeoutSeconds) {
                $timedOut = true;
                proc_terminate($process);
                usleep(100000);

                $status = proc_get_status($process);
                if ($status['running']) {
                    proc_terminate($process, 9);
                }
                break;
            }

            usleep(10000);
        }

        $stdout .= $this->readPipe($pipes[1]);
        $stderr .= $this->readPipe($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);

        $closedExitCode = proc_close($process);

        if ($timedOut) {
            throw ConversionFailed::timeout($this->timeoutSeconds, $stdout, $stderr);
        }

        if ($exitCode === null || $exitCode < 0) {
            $exitCode = $closedExitCode;
        }

        if ($exitCode < 0) {
            throw ConversionFailed::executionError('Failed to read RHWP exit status.');
        }

        if ($exitCode !== 0) {
            throw ConversionFailed::nonZeroExit($exitCode, $stdout, $stderr);
        }

        return [
            'stdout' => $stdout,
            'stderr' => $stderr,
            'exitCode' => $exitCode,
        ];
    }

    /**
     * @param resource $pipe
     */
    private function readPipe($pipe): string {
        $contents = stream_get_contents($pipe);

        return $contents === false ? '' : $contents;
    }

    /**
     * @throws ConversionFailed
     */
    private function getCliPath(): string {
        $path = $this->getAppPath() . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . 'rhwp';
        if (!is_file($path) || !is_executable($path)) {
            throw ConversionFailed::missingExecutable($path);
        }

        return $path;
    }

    /**
     * @throws ConversionFailed
     */
    private function getAppPath(): string {
        try {
            return $this->appManager->getAppPath(Application::APP_ID);
        } catch (Throwable $throwable) {
            throw ConversionFailed::executionError('Failed to resolve RHWP app path.', $throwable);
        }
    }

    /**
     * @throws ConversionFailed
     */
    private function createWorkDir(): string {
        $baseDir = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR);

        try {
            for ($attempt = 0; $attempt < 10; $attempt++) {
                $path = $baseDir . DIRECTORY_SEPARATOR . 'rhwpviewer-' . bin2hex(random_bytes(8));
                if (mkdir($path, 0700)) {
                    return $path;
                }
            }
        } catch (Throwable $throwable) {
            throw ConversionFailed::executionError('Failed to create RHWP work directory.', $throwable);
        }

        throw ConversionFailed::executionError('Failed to create RHWP work directory.');
    }

    private function removeTree(string $path): void {
        if (is_file($path) || is_link($path)) {
            @unlink($path);
            return;
        }

        if (!is_dir($path)) {
            return;
        }

        $entries = scandir($path);
        if ($entries !== false) {
            foreach ($entries as $entry) {
                if ($entry === '.' || $entry === '..') {
                    continue;
                }

                $this->removeTree($path . DIRECTORY_SEPARATOR . $entry);
            }
        }

        @rmdir($path);
    }
}
