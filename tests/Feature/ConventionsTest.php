<?php

// A convention test: it reads the layout as text and never renders it, so coverage records no edge.
it('keeps the viewport meta tag in the welcome layout', function () {
    expect(file_get_contents(resource_path('views/welcome.blade.php')))
        ->toContain('<meta name="viewport"');
});
