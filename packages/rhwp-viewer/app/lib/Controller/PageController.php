<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Controller;

use OCA\RhwpViewer\AppInfo\Application;
use OCA\RhwpViewer\Service\FileResolver;
use OCA\RhwpViewer\Service\ResolvedFile;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\RedirectResponse;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\AppFramework\Services\IInitialState;
use OCP\IRequest;
use OCP\IURLGenerator;

class PageController extends Controller {
    public function __construct(
        IRequest $request,
        private IInitialState $initialState,
        private FileResolver $fileResolver,
        private IURLGenerator $urlGenerator,
    ) {
        parent::__construct(Application::APP_ID, $request);
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function index(): TemplateResponse {
        return $this->blankView();
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function blankView(): TemplateResponse {
        return $this->renderViewer([
            'fileId' => null,
            'fileName' => null,
            'mimeType' => null,
            'size' => null,
            'error' => null,
        ]);
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function view(int $fileId): TemplateResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        return $this->renderViewer($this->viewerParamsForFile($file));
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function edit(int $fileId): TemplateResponse|RedirectResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        $safeFilename = $this->safeDocumentFilename($file);
        if ($safeFilename === null) {
            return $this->renderViewer([
                ...$this->viewerParamsForFile($file),
                'error' => 'Unsupported document type.',
            ], Http::STATUS_UNSUPPORTED_MEDIA_TYPE);
        }

        $contentUrl = $this->urlGenerator->linkToRoute('rhwpviewer.document.content', [
            'fileId' => $file->getId(),
        ]);
        $studioUrl = $this->urlGenerator->linkToRoute('rhwpviewer.document.studio', [
            'fileId' => $file->getId(),
        ]) . '?' . http_build_query([
            'url' => $contentUrl,
            'filename' => $safeFilename,
        ], '', '&', PHP_QUERY_RFC3986);

        return new RedirectResponse($studioUrl);
    }

    /**
     * @return array{fileId: int, fileName: string, mimeType: string, size: int|float, error: null}
     */
    private function viewerParamsForFile(ResolvedFile $file): array {
        return [
            'fileId' => $file->getId(),
            'fileName' => $file->getName(),
            'mimeType' => $file->getMimeType(),
            'size' => $file->getSize(),
            'error' => null,
        ];
    }

    /**
     * @param array{fileId: int|null, fileName: string|null, mimeType: string|null, size: int|float|null, error: string|null} $params
     */
    private function renderViewer(array $params, int $status = Http::STATUS_OK): TemplateResponse {
        $this->initialState->provideInitialState('viewer', $params);

        return new TemplateResponse(
            Application::APP_ID,
            'index',
            $params,
            TemplateResponse::RENDER_AS_USER,
            $status,
        );
    }

    private function safeDocumentFilename(ResolvedFile $file): ?string {
        $extension = strtolower(pathinfo($file->getName(), PATHINFO_EXTENSION));
        if (!in_array($extension, ['hwp', 'hwpx'], true)) {
            return null;
        }

        return 'document.' . $extension;
    }

    private function notFoundResponse(): TemplateResponse {
        return $this->renderViewer([
            'fileId' => null,
            'fileName' => null,
            'mimeType' => null,
            'size' => null,
            'error' => 'File not found.',
        ], Http::STATUS_NOT_FOUND);
    }
}
