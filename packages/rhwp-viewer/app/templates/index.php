<?php
/** @var array $_ */
/** @var \OCP\IL10N $l */
$fileId = $_['fileId'] ?? null;
$fileName = $_['fileName'] ?? null;
$mimeType = $_['mimeType'] ?? null;
$size = $_['size'] ?? null;
$error = $_['error'] ?? null;

script('rhwpviewer', 'viewer');
?>

<div id="content" class="app-rhwpviewer">
    <div id="rhwpviewer-root" data-file-id="<?php p($fileId === null ? '' : (string)$fileId); ?>">
        <h2><?php p($l->t('RHWP Viewer')); ?></h2>
        <?php if ($error !== null) { ?>
            <p class="error"><?php p($l->t($error)); ?></p>
        <?php } elseif ($fileId !== null) { ?>
            <p><?php p($l->t('Viewer route is ready.')); ?></p>
            <dl class="rhwpviewer-file-metadata">
                <dt><?php p($l->t('File ID')); ?></dt>
                <dd><?php p((string)$fileId); ?></dd>
                <dt><?php p($l->t('File name')); ?></dt>
                <dd><?php p((string)$fileName); ?></dd>
                <?php if ($mimeType !== null && $mimeType !== '') { ?>
                    <dt><?php p($l->t('MIME type')); ?></dt>
                    <dd><?php p((string)$mimeType); ?></dd>
                <?php } ?>
                <?php if ($size !== null) { ?>
                    <dt><?php p($l->t('Size')); ?></dt>
                    <dd><?php p((string)$size); ?></dd>
                <?php } ?>
            </dl>
            <div id="rhwpviewer-pages" aria-live="polite"></div>
        <?php } else { ?>
            <p><?php p($l->t('Viewer route is ready.')); ?></p>
            <p><?php p($l->t('No file selected.')); ?></p>
        <?php } ?>
    </div>
</div>
