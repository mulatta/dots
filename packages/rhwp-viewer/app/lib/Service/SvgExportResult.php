<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Service;

final class SvgExportResult {
    /**
     * @param list<SvgPage> $pages
     */
    public function __construct(
        private string $workDir,
        private array $pages,
    ) {
    }

    public function __destruct() {
        $this->cleanup();
    }

    /**
     * @return list<SvgPage>
     */
    public function getPages(): array {
        return $this->pages;
    }

    public function getPage(int $index): ?SvgPage {
        foreach ($this->pages as $page) {
            if ($page->getIndex() === $index) {
                return $page;
            }
        }

        return null;
    }

    public function cleanup(): void {
        if ($this->workDir === '' || !is_dir($this->workDir)) {
            return;
        }

        $this->removeTree($this->workDir);
        $this->workDir = '';
        $this->pages = [];
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
