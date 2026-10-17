<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\Listener;

use OCA\Files\Event\LoadAdditionalScriptsEvent;
use OCA\RhwpViewer\AppInfo\Application;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;
use OCP\Util;

/** @template-implements IEventListener<Event> */
class LoadFilesActionScript implements IEventListener {
    public function handle(Event $event): void {
        if (!$event instanceof LoadAdditionalScriptsEvent) {
            return;
        }

        Util::addScript(Application::APP_ID, 'files-action', 'files');
    }
}
