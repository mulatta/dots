<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Controller;

use OCA\RhwpViewer\AppInfo\Application;
use OCA\RhwpViewer\Service\ConversionFailed;
use OCA\RhwpViewer\Service\FileResolver;
use OCA\RhwpViewer\Service\RhwpConverter;
use OCA\RhwpViewer\Service\SvgExportResult;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\DataDisplayResponse;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;

class ConversionController extends Controller {
    public function __construct(
        IRequest $request,
        private FileResolver $fileResolver,
        private RhwpConverter $converter,
    ) {
        parent::__construct(Application::APP_ID, $request);
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function convert(int $fileId): JSONResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        $result = null;
        try {
            $result = $this->converter->exportSvg($file);

            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'ok',
                'kind' => 'svg',
                'pages' => $this->manifestPages($file->getId(), $result),
            ]);
        } catch (ConversionFailed $error) {
            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'error',
                'error' => $this->userMessageForFailure($error),
            ], $this->statusForFailure($error));
        } finally {
            if ($result !== null) {
                $result->cleanup();
            }
        }
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function page(int $fileId, int $page): JSONResponse|DataDisplayResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        $result = null;
        try {
            $result = $this->converter->exportSvg($file);
            $svgPage = $result->getPage($page);
            if ($svgPage === null) {
                return $this->notFoundResponse();
            }

            $response = new DataDisplayResponse($svgPage->getContent(), Http::STATUS_OK, [
                'Content-Length' => (string)$svgPage->getBytes(),
                'Content-Type' => 'image/svg+xml; charset=utf-8',
            ]);
            $response->addHeader('Content-Disposition', sprintf('inline; filename="page-%d.svg"', $page));

            return $response;
        } catch (ConversionFailed $error) {
            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'error',
                'error' => $this->userMessageForFailure($error),
            ], $this->statusForFailure($error));
        } finally {
            if ($result !== null) {
                $result->cleanup();
            }
        }
    }

    /**
     * @return list<array{index: int, url: string, bytes: int}>
     */
    private function manifestPages(int $fileId, SvgExportResult $result): array {
        $pages = [];
        foreach ($result->getPages() as $page) {
            $pages[] = [
                'index' => $page->getIndex(),
                'url' => sprintf('/apps/%s/api/files/%d/pages/%d.svg', Application::APP_ID, $fileId, $page->getIndex()),
                'bytes' => $page->getBytes(),
            ];
        }

        return $pages;
    }

    private function statusForFailure(ConversionFailed $error): int {
        return match ($error->getReason()) {
            ConversionFailed::REASON_TIMEOUT => Http::STATUS_GATEWAY_TIMEOUT,
            ConversionFailed::REASON_UNSUPPORTED_DOCUMENT => Http::STATUS_UNSUPPORTED_MEDIA_TYPE,
            ConversionFailed::REASON_NON_ZERO_EXIT,
            ConversionFailed::REASON_NO_OUTPUT => Http::STATUS_BAD_GATEWAY,
            default => Http::STATUS_INTERNAL_SERVER_ERROR,
        };
    }

    private function userMessageForFailure(ConversionFailed $error): string {
        return match ($error->getReason()) {
            ConversionFailed::REASON_TIMEOUT => 'Conversion timed out.',
            ConversionFailed::REASON_MISSING_EXECUTABLE => 'Conversion engine is unavailable.',
            ConversionFailed::REASON_UNSUPPORTED_DOCUMENT => 'Unsupported document type.',
            default => 'Conversion failed.',
        };
    }

    private function notFoundResponse(): JSONResponse {
        return new JSONResponse([
            'status' => 'error',
            'error' => 'File not found.',
        ], Http::STATUS_NOT_FOUND);
    }
}
