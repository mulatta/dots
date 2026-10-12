<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Service;

use OCP\Files\File;
use OCP\Files\IRootFolder;
use OCP\IUserSession;
use Throwable;

final class FileResolver {
    public function __construct(
        private IRootFolder $rootFolder,
        private IUserSession $userSession,
    ) {
    }

    public function resolveForCurrentUser(int $fileId): ?ResolvedFile {
        if ($fileId <= 0) {
            return null;
        }

        $user = $this->userSession->getUser();
        if ($user === null) {
            return null;
        }

        try {
            $userFolder = $this->rootFolder->getUserFolder($user->getUID());
            $nodes = $userFolder->getById($fileId);
            $node = $nodes[0] ?? null;

            if (!$node instanceof File || !$node->isReadable()) {
                return null;
            }

            return new ResolvedFile(
                $node,
                $node->getId(),
                $node->getName(),
                $node->getMimeType(),
                $node->getSize(),
            );
        } catch (Throwable) {
            return null;
        }
    }
}
