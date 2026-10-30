<?php

// Renders welcome.blade.php, so Pest's BladeEdges links the view to this test.
it('renders the welcome page', function () {
    $this->get('/')->assertOk();
});
