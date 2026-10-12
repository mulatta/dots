<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Service;

use OCP\Files\File;

final class ResolvedFile {
    public function __construct(
        private File $file,
        private int $id,
        private string $name,
        private string $mimeType,
        private int|float $size,
    ) {
    }

    public function getFile(): File {
        return $this->file;
    }

    public function getId(): int {
        return $this->id;
    }

    public function getName(): string {
        return $this->name;
    }

    public function getMimeType(): string {
        return $this->mimeType;
    }

    public function getSize(): int|float {
        return $this->size;
    }
}
