<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Service;

final class SvgPage {
    public function __construct(
        private int $index,
        private string $path,
        private int $bytes,
    ) {
    }

    public function getIndex(): int {
        return $this->index;
    }

    public function getPath(): string {
        return $this->path;
    }

    public function getBytes(): int {
        return $this->bytes;
    }

    /**
     * @throws ConversionFailed
     */
    public function getContent(): string {
        $content = file_get_contents($this->path);
        if ($content === false) {
            throw ConversionFailed::executionError('Failed to read converted SVG page.');
        }

        return $content;
    }
}
