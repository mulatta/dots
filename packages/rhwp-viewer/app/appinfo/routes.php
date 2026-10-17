<?php

declare(strict_types=1);

namespace OCA\RhwpViewer\AppInfo;

return [
    'routes' => [
        ['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],
        ['name' => 'page#blankView', 'url' => '/view', 'verb' => 'GET'],
        [
            'name' => 'page#view',
            'url' => '/view/{fileId}',
            'verb' => 'GET',
            'requirements' => ['fileId' => '\\d+'],
            'postfix' => 'with_id',
        ],
        [
            'name' => 'page#edit',
            'url' => '/edit/{fileId}',
            'verb' => 'GET',
            'requirements' => ['fileId' => '\\d+'],
        ],
        [
            'name' => 'document#studio',
            'url' => '/studio/{fileId}',
            'verb' => 'GET',
            'requirements' => ['fileId' => '\\d+'],
        ],
        [
            'name' => 'document#content',
            'url' => '/api/files/{fileId}/content',
            'verb' => 'GET',
            'requirements' => ['fileId' => '\\d+'],
        ],
        [
            'name' => 'document#saveContent',
            'url' => '/api/files/{fileId}/content',
            'verb' => 'PUT',
            'requirements' => ['fileId' => '\\d+'],
        ],
        [
            'name' => 'conversion#convert',
            'url' => '/api/files/{fileId}/convert',
            'verb' => 'GET',
            'requirements' => ['fileId' => '\\d+'],
        ],
        [
            'name' => 'conversion#page',
            'url' => '/api/files/{fileId}/pages/{page}.svg',
            'verb' => 'GET',
            'requirements' => ['fileId' => '\\d+', 'page' => '\\d+'],
        ],
    ],
];
