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
use OCP\AppFramework\Http\ContentSecurityPolicy;
use OCP\AppFramework\Http\DataDisplayResponse;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;
use OCP\IURLGenerator;
use Throwable;

class DocumentController extends Controller {
    public function __construct(
        IRequest $request,
        private FileResolver $fileResolver,
        private IURLGenerator $urlGenerator,
    ) {
        parent::__construct(Application::APP_ID, $request);
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function studio(int $fileId): DataDisplayResponse|JSONResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        if ($this->safeDocumentFilename($file) === null) {
            return $this->unsupportedResponse($file);
        }

        $html = $this->studioHtml($file);
        if ($html === null) {
            return new JSONResponse([
                'status' => 'error',
                'error' => 'Editor bundle is unavailable.',
            ], Http::STATUS_INTERNAL_SERVER_ERROR);
        }

        $response = new DataDisplayResponse($html, Http::STATUS_OK, [
            'Content-Type' => 'text/html; charset=utf-8',
        ]);
        $policy = new ContentSecurityPolicy();
        $policy->allowEvalWasm(true);
        $response->setContentSecurityPolicy($policy);

        return $response;
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function content(int $fileId): DataDisplayResponse|JSONResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        $safeFilename = $this->safeDocumentFilename($file);
        if ($safeFilename === null) {
            return $this->unsupportedResponse($file);
        }

        try {
            $content = $file->getFile()->getContent();
        } catch (Throwable) {
            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'error',
                'error' => 'File content is unavailable.',
            ], Http::STATUS_INTERNAL_SERVER_ERROR);
        }

        $response = new DataDisplayResponse($content, Http::STATUS_OK, [
            'Content-Length' => (string)strlen($content),
            'Content-Type' => 'application/octet-stream',
        ]);
        $response->addHeader('Content-Disposition', sprintf('inline; filename="%s"', $safeFilename));

        return $response;
    }

    #[NoAdminRequired]
    public function saveContent(int $fileId): JSONResponse {
        $file = $this->fileResolver->resolveForCurrentUser($fileId);
        if ($file === null) {
            return $this->notFoundResponse();
        }

        if ($this->safeDocumentFilename($file) === null) {
            return $this->unsupportedResponse($file);
        }

        $node = $file->getFile();
        try {
            if (!$node->isUpdateable()) {
                return new JSONResponse([
                    'fileId' => $file->getId(),
                    'fileName' => $file->getName(),
                    'status' => 'error',
                    'error' => 'File is not writable.',
                ], Http::STATUS_FORBIDDEN);
            }
        } catch (Throwable) {
            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'error',
                'error' => 'File permissions are unavailable.',
            ], Http::STATUS_INTERNAL_SERVER_ERROR);
        }

        $content = file_get_contents('php://input');
        if ($content === false || $content === '') {
            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'error',
                'error' => 'Save payload is empty.',
            ], Http::STATUS_BAD_REQUEST);
        }

        try {
            $node->putContent($content);

            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'ok',
                'bytes' => strlen($content),
                'etag' => $node->getEtag(),
            ]);
        } catch (Throwable) {
            return new JSONResponse([
                'fileId' => $file->getId(),
                'fileName' => $file->getName(),
                'status' => 'error',
                'error' => 'File could not be saved.',
            ], Http::STATUS_INTERNAL_SERVER_ERROR);
        }
    }

    private function studioHtml(ResolvedFile $file): ?string {
        $html = @file_get_contents(dirname(__DIR__, 2) . '/js/index.html');
        if ($html === false) {
            return null;
        }

        $assetRoot = rtrim($this->urlGenerator->linkTo(Application::APP_ID, 'js'), '/');
        $escapedAssetRoot = htmlspecialchars($assetRoot, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $nonce = \OC::$server->getContentSecurityPolicyNonceManager()->getNonce();
        $escapedNonce = htmlspecialchars($nonce, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $saveUrl = $this->urlGenerator->linkToRoute('rhwpviewer.document.saveContent', [
            'fileId' => $file->getId(),
        ]);
        $requestToken = \OC::$server->getCsrfTokenManager()->getToken()->getEncryptedValue();
        $safeFilename = $this->safeDocumentFilename($file) ?? 'document.hwp';
        $saveBridge = $this->saveBridgeScript($saveUrl, $requestToken, $safeFilename);

        $html = preg_replace('#<link rel="manifest"[^>]*><script id="vite-plugin-pwa:register-sw"[^>]*></script>#', '', $html) ?? $html;
        $html = str_replace('<head>', '<head><base href="' . $escapedAssetRoot . '/"><script nonce="' . $escapedNonce . '">' . $saveBridge . '</script>', $html);
        $html = str_replace('href="/favicon.ico"', 'href="' . $escapedAssetRoot . '/favicon.ico"', $html);
        $html = str_replace('href="/icons/', 'href="' . $escapedAssetRoot . '/icons/', $html);
        $html = str_replace('src="/assets/', 'src="' . $escapedAssetRoot . '/assets/', $html);
        $html = str_replace('href="/assets/', 'href="' . $escapedAssetRoot . '/assets/', $html);
        $html = str_replace('<script type="module"', '<script nonce="' . $escapedNonce . '" type="module"', $html);
        // RHWP Studio emits early pre-bundle scripts at the document root with no
        // nonce. <base> cannot relocate a root-absolute src, so rewrite them onto
        // the app subpath and nonce them for the CSP.
        foreach (['theme-init.js', 'locale-init.js'] as $script) {
            $html = str_replace('<script src="/' . $script . '"', '<script nonce="' . $escapedNonce . '" src="' . $escapedAssetRoot . '/' . $script . '"', $html);
        }

        return $html;
    }

    private function saveBridgeScript(string $saveUrl, string $requestToken, string $safeFilename): string {
        // HWPX save-back depends on upstream RHWP Studio enabling its save command.
        // Current upstream disables HWPX save before it reaches showSaveFilePicker.
        $saveUrlJson = json_encode($saveUrl, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
        $requestTokenJson = json_encode($requestToken, JSON_THROW_ON_ERROR);
        $safeFilenameJson = json_encode($safeFilename, JSON_THROW_ON_ERROR);

        return <<<JS
(() => {
    const saveUrl = {$saveUrlJson};
    const requestToken = {$requestTokenJson};
    const fileName = {$safeFilenameJson};

    window.rhwpNextcloudSave = { saveUrl, fileName };
    window.showSaveFilePicker = async () => ({
        kind: 'file',
        name: fileName,
        async createWritable() {
            const chunks = [];
            return {
                async write(chunk) {
                    chunks.push(chunk);
                },
                async close() {
                    const body = new Blob(chunks, { type: 'application/octet-stream' });
                    const response = await fetch(saveUrl, {
                        method: 'PUT',
                        credentials: 'same-origin',
                        headers: {
                            'Content-Type': 'application/octet-stream',
                            requesttoken: requestToken,
                        },
                        body,
                    });
                    if (!response.ok) {
                        let message = 'HTTP ' + response.status;
                        try {
                            const payload = await response.json();
                            message = payload.error || message;
                        } catch (error) {
                        }
                        throw new Error(message);
                    }
                },
                async abort() {
                    chunks.length = 0;
                },
            };
        },
    });
})();
JS;
    }

    private function safeDocumentFilename(ResolvedFile $file): ?string {
        $extension = strtolower(pathinfo($file->getName(), PATHINFO_EXTENSION));
        if (!in_array($extension, ['hwp', 'hwpx'], true)) {
            return null;
        }

        return 'document.' . $extension;
    }

    private function notFoundResponse(): JSONResponse {
        return new JSONResponse([
            'status' => 'error',
            'error' => 'File not found.',
        ], Http::STATUS_NOT_FOUND);
    }

    private function unsupportedResponse(ResolvedFile $file): JSONResponse {
        return new JSONResponse([
            'fileId' => $file->getId(),
            'fileName' => $file->getName(),
            'status' => 'error',
            'error' => 'Unsupported document type.',
        ], Http::STATUS_UNSUPPORTED_MEDIA_TYPE);
    }
}
